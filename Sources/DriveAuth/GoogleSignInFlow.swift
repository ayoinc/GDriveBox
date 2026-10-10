import AppAuth
import AppKit

/// Presents Google sign-in in an `ASWebAuthenticationSession` sheet (system WebKit). Google's own
/// page handles passkeys, security keys, and every 2-Step Verification method; the app only
/// receives the authorization code, exchanged for tokens with PKCE.
@MainActor
public final class GoogleSignInFlow {
    private let configuration: GoogleOAuthConfiguration
    /// AppAuth requires the session to stay alive until its callback fires.
    private var inFlight: (any OIDExternalUserAgentSession)?

    public init(configuration: GoogleOAuthConfiguration) {
        self.configuration = configuration
    }

    /// Runs the authorization-code + PKCE flow and returns the archived auth state for
    /// `AuthSession.start(archivedState:store:)`.
    /// - Parameter prefersEphemeralSession: `true` uses a private browser session that does not
    ///   reuse the user's Safari Google sign-in.
    public func signIn(presenting window: NSWindow, prefersEphemeralSession: Bool) async throws -> Data {
        let request = OIDAuthorizationRequest(
            configuration: OIDServiceConfiguration(
                authorizationEndpoint: GoogleOAuthConfiguration.authorizationEndpoint,
                tokenEndpoint: GoogleOAuthConfiguration.tokenEndpoint
            ),
            clientId: configuration.clientID,
            scopes: configuration.scopes,
            redirectURL: configuration.redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )

        return try await withCheckedThrowingContinuation { continuation in
            inFlight = OIDAuthState.authState(
                byPresenting: request,
                presenting: window,
                prefersEphemeralSession: prefersEphemeralSession
            ) { @Sendable [weak self] authState, error in
                if let authState {
                    continuation.resume(with: Result {
                        try NSKeyedArchiver.archivedData(withRootObject: authState, requiringSecureCoding: true)
                    })
                } else {
                    continuation.resume(throwing: Self.map(error))
                }
                Task { @MainActor in self?.inFlight = nil }
            }
        }
    }

    private nonisolated static func map(_ error: (any Error)?) -> any Error {
        guard let error else { return AuthError.noAccessToken }
        let nsError = error as NSError
        if nsError.domain == OIDGeneralErrorDomain, nsError.code == OIDErrorCode.userCanceledAuthorizationFlow.rawValue {
            return AuthError.cancelled
        }
        return error
    }
}
