// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SyncCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DriveAPI", targets: ["DriveAPI"]),
        .library(name: "DriveAuth", targets: ["DriveAuth"]),
        .executable(name: "GDriveBoxApp", targets: ["GDriveBoxApp"]),
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
        .executableTarget(name: "GDriveBoxApp", dependencies: ["DriveAPI", "DriveAuth"]),
        .testTarget(name: "DriveAPITests", dependencies: ["DriveAPI"]),
        .testTarget(
            name: "DriveAuthTests",
            dependencies: [
                "DriveAuth",
                .product(name: "AppAuth", package: "AppAuth-iOS"),
            ]
        ),
    ]
)
