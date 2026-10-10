import Foundation

/// Sends one HTTP request. Production code uses `URLSessionTransport`; tests inject a scripted fake.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DriveError.invalidResponse
        }
        return (data, http)
    }
}

/// Supplies OAuth access tokens to the Drive client.
public protocol AccessTokenProvider: Sendable {
    /// Returns a usable access token. With `forceRefresh` the provider must obtain a new token
    /// instead of returning the one it handed out before (the server rejected it with 401).
    func accessToken(forceRefresh: Bool) async throws -> String
}
