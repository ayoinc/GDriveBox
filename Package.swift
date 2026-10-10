// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SyncCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DriveAPI", targets: ["DriveAPI"]),
        .library(name: "DriveAuth", targets: ["DriveAuth"]),
        .executable(name: "GDriveBoxApp", targets: ["GDriveBoxApp"]),
        // Bundled by Scripts/build-app.sh as GDriveBox.app/Contents/PlugIns/GDriveBoxFileProvider.appex.
        .executable(name: "GDriveBoxFileProvider", targets: ["GDriveBoxFileProvider"]),
    ],
    dependencies: [
        .package(url: "https://github.com/openid/AppAuth-iOS.git", from: "3.0.0"),
    ],
    targets: [
        .target(name: "DriveAPI"),
        .target(
            name: "DriveAuth",
            dependencies: [
                "DriveAPI",
                .product(name: "AppAuth", package: "AppAuth-iOS"),
            ]
        ),
        // Settings both bundles must agree on (keychain item, app group).
        .target(name: "GDriveBoxShared", dependencies: ["DriveAuth"]),
        .executableTarget(name: "GDriveBoxApp", dependencies: ["DriveAPI", "DriveAuth", "GDriveBoxShared"]),
        // An app extension has no `main`: like Xcode, enter Foundation's NSExtensionMain directly.
        // (ExtensionFoundation calls a `main` symbol if the image has one, so a Swift main that
        // forwards to NSExtensionMain recurses until the stack overflows.)
        .executableTarget(
            name: "GDriveBoxFileProvider",
            dependencies: ["DriveAPI", "DriveAuth", "GDriveBoxShared"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]
        ),
        .testTarget(name: "DriveAPITests", dependencies: ["DriveAPI"]),
        .testTarget(
            name: "DriveAuthTests",
            dependencies: [
                "DriveAPI",
                "DriveAuth",
                .product(name: "AppAuth", package: "AppAuth-iOS"),
            ]
        ),
        .testTarget(name: "GDriveBoxFileProviderTests", dependencies: ["GDriveBoxFileProvider"]),
    ]
)
