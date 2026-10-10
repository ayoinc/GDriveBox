import AppAuth
import DriveAPI
import Foundation

/// Owns the signed-in user's OAuth state, hands out fresh access tokens, and persists the state
/// whenever a refresh replaces the tokens. One instance per process (app or extension).
public actor AuthSession: AccessTokenProvider {
    private let state: OIDAuthState
    private let store: any TokenStore

    /// Saves a newly signed-in state (from `GoogleSignInFlow.signIn`) and starts a session.
    public static func start(archivedState: Data, store: any TokenStore) throws -> AuthSession {
        let session = try AuthSession(archivedState: archivedState, store: store)
        try store.save(archivedState)
        return session
    }

    /// The previously saved session, or nil when nobody is signed in.
    public static func restore(from store: any TokenStore) throws -> AuthSession? {
        guard let data = try store.load() else { return nil }
        return try AuthSession(archivedState: data, store: store)
    }

    private init(archivedState: Data, store: any TokenStore) throws {
        guard let state = try? NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: archivedState) else {
            throw AuthError.corruptStoredState
        }
        self.state = state
        self.store = store
    }

    public func accessToken(forceRefresh: Bool) async throws -> String {
        if forceRefresh { state.setNeedsTokenRefresh() }
        let tokenResponseBefore = state.lastTokenResponse

        let token: String = try await withCheckedThrowingContinuation { continuation in
            state.performAction { @Sendable accessToken, _, error in
                // A failed refresh reports the error together with the stale token; the error wins.
                if let error {
                    continuation.resume(throwing: Self.map(error))
                } else if let accessToken {
                    continuation.resume(returning: accessToken)
                } else {
                    continuation.resume(throwing: AuthError.noAccessToken)
                }
            }
        }

        if state.lastTokenResponse !== tokenResponseBefore {
            try store.save(NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true))
        }
        return token
    }

    private static func map(_ error: any Error) -> any Error {
        let nsError = error as NSError
        if nsError.domain == OIDOAuthTokenErrorDomain, nsError.code == OIDErrorCodeOAuthToken.invalidGrant.rawValue {
            return AuthError.reauthenticationRequired
        }
        return error
    }
}
