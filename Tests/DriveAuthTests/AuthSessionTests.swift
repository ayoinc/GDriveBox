import AppAuth
import Foundation
import Synchronization
import Testing
@testable import DriveAuth

// MARK: - Fakes

/// Token endpoint stub served through AppAuth's real URLSession stack.
private final class StubTokenEndpoint: URLProtocol {
    enum Reply: Sendable {
        case json(status: Int, body: String)
        case failure(URLError.Code)
    }

    static let state = Mutex<(reply: Reply?, requests: Int)>((nil, 0))

    static var requestCount: Int { state.withLock { $0.requests } }

    static func install(_ reply: Reply) {
        state.withLock { $0 = (reply, 0) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubTokenEndpoint.self]
        OIDURLSessionProvider.setSession(URLSession(configuration: configuration))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let reply = Self.state.withLock { state -> Reply? in
            state.requests += 1
            return state.reply
        }
        switch reply {
        case let .json(status, body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
        }
    }
}

private final class InMemoryTokenStore: TokenStore {
    private let data: Mutex<Data?>

    init(_ initial: Data? = nil) { data = Mutex(initial) }

    func load() -> Data? { data.withLock { $0 } }
    func save(_ newData: Data) { data.withLock { $0 = newData } }
    func delete() { data.withLock { $0 = nil } }
}

/// An archived state as `GoogleSignInFlow.signIn` would return it, pointing at a fake token endpoint.
private func archivedSignedInState(accessToken: String = "old-token", expiresIn: Int = 3600) throws -> Data {
    let configuration = OIDServiceConfiguration(
        authorizationEndpoint: URL(string: "https://auth.invalid/auth")!,
        tokenEndpoint: URL(string: "https://auth.invalid/token")!
    )
    let authorizationRequest = OIDAuthorizationRequest(
        configuration: configuration,
        clientId: "client-id",
        scopes: ["openid"],
        redirectURL: URL(string: "com.example.app:/oauthredirect")!,
        responseType: OIDResponseTypeCode,
        additionalParameters: nil
    )
    let authorizationResponse = OIDAuthorizationResponse(request: authorizationRequest, parameters: ["code": "auth-code" as NSString])
    let tokenParameters: [String: NSCopying & NSObjectProtocol] = [
        "access_token": accessToken as NSString,
        "refresh_token": "refresh-1" as NSString,
        "expires_in": expiresIn as NSNumber,
        "token_type": "Bearer" as NSString,
    ]
    let tokenResponse = OIDTokenResponse(request: try #require(authorizationResponse.tokenExchangeRequest()), parameters: tokenParameters)
    let state = OIDAuthState(authorizationResponse: authorizationResponse, tokenResponse: tokenResponse)
    return try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true)
}

// MARK: - Tests

/// Serialized: AppAuth's URLSession provider and the stub are process-global.
@Suite(.serialized) struct AuthSessionTests {
    @Test func unexpiredTokenIsReturnedWithoutRefreshing() async throws {
        StubTokenEndpoint.install(.json(status: 500, body: "{}"))
        let session = try AuthSession.start(archivedState: archivedSignedInState(), store: InMemoryTokenStore())

        #expect(try await session.accessToken(forceRefresh: false) == "old-token")
        #expect(StubTokenEndpoint.requestCount == 0)
    }

    @Test func forcedRefreshReturnsNewTokenAndPersistsIt() async throws {
        StubTokenEndpoint.install(.json(status: 200, body: #"{"access_token":"new-token","expires_in":3600,"token_type":"Bearer"}"#))
        let store = InMemoryTokenStore()
        let session = try AuthSession.start(archivedState: archivedSignedInState(), store: store)

        #expect(try await session.accessToken(forceRefresh: true) == "new-token")

        // Another process restoring from the shared store gets the refreshed token without network.
        let restored = try #require(try AuthSession.restore(from: store))
        #expect(try await restored.accessToken(forceRefresh: false) == "new-token")
        #expect(StubTokenEndpoint.requestCount == 1)
    }

    @Test func invalidGrantRequiresReauthentication() async throws {
        StubTokenEndpoint.install(.json(status: 400, body: #"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#))
        let session = try AuthSession.start(archivedState: archivedSignedInState(), store: InMemoryTokenStore())

        await #expect(throws: AuthError.reauthenticationRequired) {
            try await session.accessToken(forceRefresh: true)
        }
    }

    @Test func networkFailureDuringRefreshThrowsInsteadOfReturningStaleToken() async throws {
        StubTokenEndpoint.install(.failure(.notConnectedToInternet))
        let session = try AuthSession.start(archivedState: archivedSignedInState(), store: InMemoryTokenStore())

        let error = await #expect(throws: (any Error).self) {
            try await session.accessToken(forceRefresh: true)
        }
        #expect(error as? AuthError != .reauthenticationRequired)
    }

    @Test func undecodableStoredStateIsRejected() {
        #expect(throws: AuthError.corruptStoredState) {
            try AuthSession.restore(from: InMemoryTokenStore(Data("garbage".utf8)))
        }
    }

    @Test func emptyStoreMeansSignedOut() throws {
        #expect(try AuthSession.restore(from: InMemoryTokenStore()) == nil)
    }
}

@Test func redirectURLIsReversedClientID() throws {
    let configuration = try GoogleOAuthConfiguration(clientID: "123456789012-abc123def.apps.googleusercontent.com")
    #expect(configuration.redirectURL.absoluteString == "com.googleusercontent.apps.123456789012-abc123def:/oauthredirect")
}

@Test(arguments: [
    "",
    ".apps.googleusercontent.com",
    "123-abc.apps.example.com",
    "123 abc.apps.googleusercontent.com",
    "123/abc.apps.googleusercontent.com",
])
func malformedClientIDsAreRejected(_ clientID: String) {
    #expect(throws: AuthError.invalidClientID(clientID)) {
        try GoogleOAuthConfiguration(clientID: clientID)
    }
}
