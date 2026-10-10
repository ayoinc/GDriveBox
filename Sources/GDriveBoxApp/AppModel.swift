import AppKit
import DriveAPI
import DriveAuth
import Foundation
import Observation
import Security

/// All app state: the signed-in session, the account summary, and the My Drive root listing.
@MainActor
@Observable
final class AppModel {
    enum Listing: Equatable {
        case idle
        case loading
        /// `isTruncated` is true when Drive has more than one page of root items.
        case loaded(files: [DriveFile], isTruncated: Bool)
        case failed(Problem)
    }

    private(set) var account: About?
    private(set) var listing: Listing = .idle
    private(set) var isSigningIn = false
    private(set) var isSigningOut = false
    /// A sign-in waiting for the drive window to exist so it can anchor the Google sheet.
    private(set) var isSignInPending = false
    /// A failed restore, sign-in, or sign-out; listing failures live in `listing`.
    private(set) var sessionProblem: Problem?
    /// The GDriveBox folder could not be added to Finder.
    private(set) var finderFolderProblem: Problem?
    /// macOS keeps the GDriveBox folder empty until the user turns the extension on in System Settings.
    private(set) var finderFolderNeedsEnabling = false
    /// Shown while signed out, e.g. when Google could not be told about the sign-out.
    private(set) var notice: String?

    private let clientID: String?
    private let tokenStore: any TokenStore
    private var session: AuthSession?
    private var client: DriveClient?
    /// Bumped whenever the session changes, so work started for an old session drops its result.
    private var sessionGeneration = 0

    var isSignedIn: Bool { client != nil }

    init(clientID: String?, tokenStore: any TokenStore) {
        self.clientID = clientID
        self.tokenStore = tokenStore
        restoreSession()
    }

    /// Asks the drive window to start sign-in once it is on screen.
    func requestSignIn() {
        guard !isSigningIn else { return }
        isSignInPending = true
    }

    func signIn(presenting window: NSWindow) async {
        isSignInPending = false
        guard !isSigningIn else { return }
        sessionProblem = nil
        notice = nil
        isSigningIn = true
        let session: AuthSession
        do {
            guard let clientID else { throw ConfigurationError.missingClientID }
            let flow = GoogleSignInFlow(configuration: try GoogleOAuthConfiguration(clientID: clientID))
            let archivedState = try await flow.signIn(presenting: window, prefersEphemeralSession: false)
            session = try AuthSession.start(archivedState: archivedState, store: tokenStore)
        } catch AuthError.cancelled {
            isSigningIn = false
            return
        } catch {
            isSigningIn = false
            sessionProblem = Problem(error)
            return
        }
        isSigningIn = false
        adopt(session)
        await refresh()
    }

    /// Revokes Google's grant, then removes the Finder folder with every downloaded copy and the
    /// saved sign-in (the privacy policy promises all three).
    func signOut() async {
        guard let session, !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        var problem: Problem?
        var revocationFailed = false

        // Local sign-out proceeds even when Google is unreachable; the notice says so.
        do {
            try await session.revoke()
        } catch {
            revocationFailed = true
        }
        do {
            try tokenStore.delete()
        } catch {
            problem = Problem(error)
        }
        do {
            try await FinderFolder.remove()
        } catch {
            problem = problem ?? Problem(
                title: "Couldn't remove the GDriveBox folder",
                message: error.localizedDescription,
                recovery: .none
            )
        }

        sessionGeneration += 1
        self.session = nil
        client = nil
        account = nil
        listing = .idle
        finderFolderProblem = nil
        finderFolderNeedsEnabling = false
        sessionProblem = problem
        notice = revocationFailed
            ? "Signed out on this Mac, but Google couldn't be reached to revoke access. You can remove GDriveBox at myaccount.google.com/connections."
            : nil
    }

    /// Re-registers the Finder folder and reloads the account summary and the My Drive root listing.
    func refresh() async {
        guard let client, listing != .loading else { return }
        let generation = sessionGeneration
        listing = .loading
        await connectFinderFolder()
        do {
            async let about = client.about()
            async let page = client.listFiles(.children(of: DriveFile.myDriveRootID))
            let (loadedAbout, loadedPage) = try await (about, page)
            guard generation == sessionGeneration else { return }
            account = loadedAbout
            listing = .loaded(files: Self.sorted(loadedPage.files), isTruncated: loadedPage.nextPageToken != nil)
        } catch {
            guard generation == sessionGeneration else { return }
            listing = .failed(Problem(error))
        }
    }

    /// Registers the File Provider domain; idempotent, so it runs on every refresh while signed in.
    private func connectFinderFolder() async {
        let generation = sessionGeneration
        do {
            let isEnabled = try await FinderFolder.register()
            guard generation == sessionGeneration else { return }
            finderFolderProblem = nil
            finderFolderNeedsEnabling = !isEnabled
        } catch {
            guard generation == sessionGeneration else { return }
            finderFolderProblem = Problem(
                title: "Couldn't add GDriveBox to Finder",
                message: error.localizedDescription,
                recovery: .none
            )
        }
    }

    private func restoreSession() {
        do {
            guard let session = try AuthSession.restore(from: tokenStore) else { return }
            adopt(session)
            Task { await refresh() }
        } catch {
            sessionProblem = Problem(error)
        }
    }

    private func adopt(_ session: AuthSession) {
        sessionGeneration += 1
        self.session = session
        client = DriveClient(tokens: session)
        account = nil
        listing = .idle
    }

    /// Folders first, then Finder-style name order.
    private static func sorted(_ files: [DriveFile]) -> [DriveFile] {
        files.sorted { lhs, rhs in
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

enum ConfigurationError: Error {
    case missingClientID
}

/// A user-facing error with the one recovery action the window offers for it.
struct Problem: Equatable {
    enum Recovery: Equatable {
        case signInAgain
        case retry
        case none
    }

    let title: String
    let message: String
    let recovery: Recovery

    init(_ error: any Error) {
        switch error {
        case AuthError.reauthenticationRequired, DriveError.unauthorized:
            self.init(
                title: "Sign in again",
                message: "Google no longer accepts the saved sign-in.",
                recovery: .signInAgain
            )
        case AuthError.corruptStoredState:
            self.init(title: "Sign in again", message: "The saved sign-in could not be read.", recovery: .signInAgain)
        case AuthError.keychain(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown keychain error"
            self.init(title: "Keychain error \(status)", message: detail, recovery: .none)
        case AuthError.invalidClientID(let clientID):
            self.init(title: "Invalid Google client ID", message: clientID, recovery: .none)
        case ConfigurationError.missingClientID:
            self.init(
                title: "Missing Google client ID",
                message: "GDBGoogleClientID is not set in the app's Info.plist.",
                recovery: .none
            )
        case DriveError.http(let status, let apiError):
            self.init(
                title: "Google Drive error \(status)",
                message: apiError?.message ?? HTTPURLResponse.localizedString(forStatusCode: status),
                recovery: .retry
            )
        default:
            self.init(title: "Couldn't load My Drive", message: error.localizedDescription, recovery: .retry)
        }
    }

    init(title: String, message: String, recovery: Recovery) {
        self.title = title
        self.message = message
        self.recovery = recovery
    }
}
