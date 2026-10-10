import Foundation

public enum AuthError: Error, Sendable, Equatable {
    /// Not an iOS-type Google OAuth client ID.
    case invalidClientID(String)
    /// The user closed the sign-in sheet.
    case cancelled
    /// Google rejected the refresh token (`invalid_grant`): revoked, expired, or password changed.
    /// The user must sign in again.
    case reauthenticationRequired
    /// The stored auth state could not be decoded.
    case corruptStoredState
    /// AppAuth reported neither a token nor an error.
    case noAccessToken
    /// A keychain call failed with this `OSStatus`.
    case keychain(OSStatus)
    /// Google's revocation endpoint answered with this HTTP status.
    case revocationFailed(status: Int)
}
