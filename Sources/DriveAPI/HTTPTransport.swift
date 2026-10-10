import Foundation

/// Sends one HTTP request. Production code uses `URLSessionTransport`; tests inject a scripted fake.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Streams the response body to a new temporary file the caller owns (moves or deletes), so
    /// large downloads never sit in memory.
    func download(_ request: URLRequest) async throws -> (URL, HTTPURLResponse)
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

    public func download(_ request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        // Unlike the completion-handler API, the async API leaves the file for the caller.
        let (file, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: file)
            throw DriveError.invalidResponse
        }
        return (file, http)
    }
}

/// Supplies OAuth access tokens to the Drive client.
public protocol AccessTokenProvider: Sendable {
    /// Returns a usable access token. With `forceRefresh` the provider must obtain a new token
    /// instead of returning the one it handed out before (the server rejected it with 401).
    func accessToken(forceRefresh: Bool) async throws -> String
}
