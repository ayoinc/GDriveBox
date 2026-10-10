import DriveAuth
import SwiftUI

@main
struct GDriveBoxApp: App {
    static let driveWindowID = "drive"

    // The macOS 27 SDK declares `@State` as a macro whose plugin ships only with Xcode, so the
    // property-wrapper type is used directly (SwiftUI still discovers it as a `DynamicProperty`).
    private let model = State(initialValue: AppModel(
        clientID: Bundle.main.object(forInfoDictionaryKey: "GDBGoogleClientID") as? String,
        tokenStore: KeychainTokenStore(
            service: "io.github.ayoinc.GDriveBox",
            account: "google",
            accessGroup: "group.io.github.ayoinc.GDriveBox"
        )
    ))

    var body: some Scene {
        MenuBarExtra("GDriveBox", systemImage: "externaldrive.badge.icloud") {
            MenuContent(model: model.wrappedValue)
        }

        Window("My Drive", id: Self.driveWindowID) {
            DriveWindow(model: model.wrappedValue)
        }
        .defaultSize(width: 720, height: 480)
        .defaultLaunchBehavior(.suppressed)
    }
}
