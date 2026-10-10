import Foundation

/// Google OAuth settings for an iOS-type OAuth client, which Google uses for native macOS apps.
public struct GoogleOAuthConfiguration: Sendable, Equatable {
    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    public static let driveScopes = ["openid", "email", "profile", "https://www.googleapis.com/auth/drive"]

    private static let clientIDSuffix = ".apps.googleusercontent.com"

    public let clientID: String
    /// Google's redirect for iOS-type clients: the reversed client ID as a custom scheme.
    public let redirectURL: URL
    public let scopes: [String]

    /// - Parameter clientID: `<project-number>-<hash>.apps.googleusercontent.com`.
    public init(clientID: String, scopes: [String] = driveScopes) throws {
        let prefix = clientID.dropLast(Self.clientIDSuffix.count)
        guard clientID.hasSuffix(Self.clientIDSuffix),
              !prefix.isEmpty,
              prefix.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
              let redirectURL = URL(string: "com.googleusercontent.apps.\(prefix):/oauthredirect")
        else {
            throw AuthError.invalidClientID(clientID)
        }
        self.clientID = clientID
        self.redirectURL = redirectURL
        self.scopes = scopes
    }
}
