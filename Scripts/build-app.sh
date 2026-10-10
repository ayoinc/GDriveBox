#!/usr/bin/env bash
# Builds, bundles, and codesigns build/GDriveBox.app with SwiftPM and the Command Line Tools
# (no Xcode).
#
# Environment:
#   SIGN_IDENTITY         codesign identity; default "-" (ad-hoc).
#   PROVISIONING_PROFILE  .provisionprofile embedded as Contents/embedded.provisionprofile. Together
#                         with a real SIGN_IDENTITY it enables the full entitlements (app group).
#   PROVISIONING_PROFILE_GDriveBoxFileProvider
#                         The same for the embedded File Provider extension (its own App ID).
#   VERSION               CFBundleShortVersionString; default 0.1.0.
#   BUILD_NUMBER          CFBundleVersion; default 1.
#
# Ad-hoc builds (or builds without a profile) drop the profile-gated entitlements so they still
# launch; the data-protection keychain then fails with errSecMissingEntitlement (-34018).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly APP_NAME="GDriveBox"
readonly APP_PRODUCT="GDriveBoxApp"
readonly PACKAGING="$ROOT/Packaging"
readonly BUILD_DIR="$ROOT/build"
readonly APP="$BUILD_DIR/$APP_NAME.app"
readonly WORK_DIR="$BUILD_DIR/work"

# SwiftPM executable products embedded as Contents/PlugIns/<name>.appex. Each one needs
# Packaging/<name>/Info.plist and Packaging/<name>/<name>.entitlements; its profile comes from
# PROVISIONING_PROFILE_<name>.
readonly EXTENSION_PRODUCTS=("GDriveBoxFileProvider")

# Entitlements that only a provisioning profile can authorize.
readonly PROFILE_GATED_ENTITLEMENTS=(
    "com.apple.security.application-groups"
)

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
PROVISIONING_PROFILE="${PROVISIONING_PROFILE:-}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
readonly SIGN_IDENTITY PROVISIONING_PROFILE VERSION BUILD_NUMBER

readonly SWIFT_BUILD_FLAGS=(-c release --arch arm64)

die() {
    echo "error: $*" >&2
    exit 1
}

build_products() {
    local product
    for product in "$APP_PRODUCT" ${EXTENSION_PRODUCTS[@]+"${EXTENSION_PRODUCTS[@]}"}; do
        echo "==> swift build --product $product"
        swift build --package-path "$ROOT" "${SWIFT_BUILD_FLAGS[@]}" --product "$product"
    done
    BIN_DIR="$(swift build --package-path "$ROOT" "${SWIFT_BUILD_FLAGS[@]}" --show-bin-path)"
    readonly BIN_DIR
}

# fill_info_plist <template> <destination> <executable name>
fill_info_plist() {
    local template="$1" destination="$2" executable="$3"
    cp "$template" "$destination"
    plutil -replace CFBundleExecutable -string "$executable" "$destination"
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$destination"
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$destination"
    if grep -q '__[A-Z_]*__' "$destination"; then
        die "unfilled placeholder in $destination"
    fi
    plutil -lint "$destination"
}

assemble_app() {
    echo "==> Assembling $APP"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp "$BIN_DIR/$APP_PRODUCT" "$APP/Contents/MacOS/$APP_NAME"
    fill_info_plist "$PACKAGING/Info.plist" "$APP/Contents/Info.plist" "$APP_NAME"
    printf 'APPL????' >"$APP/Contents/PkgInfo"
    copy_resource_bundles
    make_app_icon
}

# Contents/Resources/AppIcon.icns from the 1024 px master Packaging/AppIcon-1024.png.
make_app_icon() {
    local master="$PACKAGING/AppIcon-1024.png" iconset="$WORK_DIR/AppIcon.iconset" size
    [[ -f "$master" ]] || die "app icon not found: $master"
    rm -rf "$iconset"
    mkdir -p "$iconset"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$master" --out "$iconset/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$master" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil --convert icns --output "$APP/Contents/Resources/AppIcon.icns" "$iconset"
}

# SwiftPM resource bundles of the linked packages (AppAuth's privacy manifests).
copy_resource_bundles() {
    local bundle
    for bundle in "$BIN_DIR"/*.bundle; do
        [[ -d "$bundle" ]] || continue
        cp -R "$bundle" "$APP/Contents/Resources/"
    done
}

# Copies each extension product into Contents/PlugIns/<name>.appex.
embed_extensions() {
    local name appex
    for name in ${EXTENSION_PRODUCTS[@]+"${EXTENSION_PRODUCTS[@]}"}; do
        appex="$APP/Contents/PlugIns/$name.appex"
        echo "==> Embedding $name.appex"
        mkdir -p "$appex/Contents/MacOS"
        cp "$BIN_DIR/$name" "$appex/Contents/MacOS/$name"
        fill_info_plist "$PACKAGING/$name/Info.plist" "$appex/Contents/Info.plist" "$name"
    done
}

uses_full_entitlements() {
    local profile="$1"
    [[ "$SIGN_IDENTITY" != "-" && -n "$profile" ]]
}

# prepare_entitlements <template> <profile or ""> <output>
# Full: the template plus the application and team identifiers from the profile, which Xcode
# would otherwise inject. Otherwise: the template without profile-gated entitlements.
prepare_entitlements() {
    local template="$1" profile="$2" output="$3" key app_id team_id
    cp "$template" "$output"
    if uses_full_entitlements "$profile"; then
        security cms -D -i "$profile" >"$WORK_DIR/profile.plist"
        app_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$WORK_DIR/profile.plist")"
        team_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$WORK_DIR/profile.plist")"
        /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $app_id" "$output"
        /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $team_id" "$output"
    else
        for key in "${PROFILE_GATED_ENTITLEMENTS[@]}"; do
            /usr/libexec/PlistBuddy -c "Delete :$key" "$output" 2>/dev/null || true
        done
    fi
    plutil -lint "$output" >/dev/null
}

# sign_bundle <bundle> <entitlements template> <profile or "">
sign_bundle() {
    local bundle="$1" template="$2" profile="$3" entitlements
    entitlements="$WORK_DIR/$(basename "$bundle").entitlements"
    if [[ -n "$profile" ]]; then
        [[ -f "$profile" ]] || die "provisioning profile not found: $profile"
        cp "$profile" "$bundle/Contents/embedded.provisionprofile"
    fi
    if ! uses_full_entitlements "$profile"; then
        echo "note: $(basename "$bundle"): signing without profile-gated entitlements (needs a real SIGN_IDENTITY and a profile)"
    fi
    prepare_entitlements "$template" "$profile" "$entitlements"
    echo "==> Signing $(basename "$bundle") as '$SIGN_IDENTITY'"
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none \
        --entitlements "$entitlements" "$bundle"
}

# Inside-out: extensions before the app that seals them.
sign_all() {
    local name profile_var
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"
    for name in ${EXTENSION_PRODUCTS[@]+"${EXTENSION_PRODUCTS[@]}"}; do
        profile_var="PROVISIONING_PROFILE_$name"
        sign_bundle "$APP/Contents/PlugIns/$name.appex" "$PACKAGING/$name/$name.entitlements" "${!profile_var:-}"
    done
    sign_bundle "$APP" "$PACKAGING/$APP_NAME.entitlements" "$PROVISIONING_PROFILE"
}

verify() {
    echo "==> Verifying"
    codesign --verify --deep --strict --verbose=2 "$APP"
    codesign -dv "$APP" 2>&1
    codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p -
}

main() {
    build_products
    assemble_app
    embed_extensions
    sign_all
    verify
    echo "==> Built $APP"
}

main "$@"
