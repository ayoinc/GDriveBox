# GDriveBox

Google Drive as a folder in Finder. Files show up instantly and download only when you open them, so they don't fill your Mac.

Website: [gdrivebox.app](https://gdrivebox.app) · Support: [support@gdrivebox.app](mailto:support@gdrivebox.app)

**Status:** early development. Not ready for daily use yet; see [BOARD.md](BOARD.md) for progress.

## Requirements

- Mac with Apple silicon (M1 or later)
- macOS 15 Sequoia or later

## How it works

- A menu-bar app signs you in through Google's own sign-in page (`ASWebAuthenticationSession`), so passkeys and every 2-Step Verification method work.
- A File Provider extension (the same macOS technology iCloud Drive uses) shows your Drive under `~/Library/CloudStorage` and in the Finder sidebar, downloading files on demand. macOS asks you once to turn it on (System Settings › General › Login Items & Extensions › File Providers). Google Docs, Sheets, and Slides appear as `.webloc` links that open in the browser. Read-only for now.
- **Sign Out** (menu bar or window) revokes GDriveBox's access at Google and removes the saved sign-in, the Finder folder, and every downloaded copy from your Mac.
- Everything runs on your Mac and talks only to Google. There is no GDriveBox server. See the [privacy policy](https://gdrivebox.app/privacy).

## Build from source

Only the Xcode Command Line Tools are needed (Swift 6).

```sh
swift build
swift test          # with Command Line Tools only, re-run once if it fails with "TestingMacros not found"
```

`Scripts/build-app.sh` assembles and codesigns `build/GDriveBox.app` with the extension embedded. A build that can use the Finder folder needs an Apple Development identity and one development provisioning profile per bundle:

```sh
SIGN_IDENTITY="Apple Development: …" \
PROVISIONING_PROFILE=path/to/app.provisionprofile \
PROVISIONING_PROFILE_GDriveBoxFileProvider=path/to/extension.provisionprofile \
Scripts/build-app.sh
```

## Layout

| Path | What |
|---|---|
| `Sources/DriveAPI` | Google Drive v3 REST client (token refresh, backoff, paging, downloads) |
| `Sources/DriveAuth` | Google sign-in (AppAuth + PKCE), Keychain token storage, revocation |
| `Sources/GDriveBoxApp` | Menu-bar app: sign in/out, registers the Finder folder |
| `Sources/GDriveBoxFileProvider` | File Provider extension behind the Finder folder |
| `Sources/GDriveBoxShared` | Identifiers the app and extension share (app group, keychain item) |
| `Packaging/`, `Scripts/build-app.sh` | Info.plists, entitlements, app icon, bundle + codesign script |
| `docs/` | Website: homepage, privacy policy, terms |
| `BOARD.md` | Kanban board: work in progress and decisions |

## License

[Apache License 2.0](LICENSE)
