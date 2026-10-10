import SwiftUI

/// The menu-bar extra's menu.
struct MenuContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(accountLabel)

        Divider()

        if model.isSignedIn {
            Button("Sign Out") {
                Task { await model.signOut() }
            }
            .disabled(model.isSigningOut)
        } else {
            Button("Sign In with Google…") {
                model.requestSignIn()
                showDriveWindow()
            }
            .disabled(model.isSigningIn)
        }

        Button("Show My Drive…") {
            showDriveWindow()
        }

        Divider()

        Button("Quit GDriveBox") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var accountLabel: String {
        if let email = model.account?.user.emailAddress { return email }
        return model.isSignedIn ? "Signed in" : "Not signed in"
    }

    /// A menu-bar-only app is never frontmost on its own, so activate it to bring the window forward.
    private func showDriveWindow() {
        openWindow(id: GDriveBoxApp.driveWindowID)
        NSApplication.shared.activate()
    }
}
