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
    /// A sign-in waiting for the drive window to exist so it can anchor the Google sheet.
    private(set) var isSignInPending = false
    /// A failed restore or sign-in; listing failures live in `listing`.
    private(set) var sessionProblem: Problem?

    private let clientID: String?
    private let tokenStore: any TokenStore
    private var client: DriveClient?

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

    /// Reloads the account summary and the My Drive root listing.
    func refresh() async {
        guard let client, listing != .loading else { return }
        listing = .loading
        do {
            async let about = client.about()
            async let page = client.listFiles(.children(of: DriveFile.myDriveRootID))
            let (loadedAbout, loadedPage) = try await (about, page)
            account = loadedAbout
            listing = .loaded(files: Self.sorted(loadedPage.files), isTruncated: loadedPage.nextPageToken != nil)
        } catch {
            listing = .failed(Problem(error))
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
