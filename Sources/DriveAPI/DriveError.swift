import Foundation

public enum DriveError: Error, Sendable, Equatable {
    /// The access token was rejected even after one forced refresh.
    case unauthorized(GoogleAPIError?)
    /// Non-success HTTP status that was not retried, or retries were exhausted.
    case http(status: Int, error: GoogleAPIError?)
    /// The response was not HTTP.
    case invalidResponse
    /// The response body did not match the expected shape.
    case decoding(String)
}

/// The `error` object Google APIs return in failed responses:
/// `{"error": {"code": 403, "message": "...", "errors": [{"reason": "..."}], "status": "..."}}`.
public struct GoogleAPIError: Sendable, Equatable {
    public let code: Int
    public let message: String
    public let reasons: [String]
    public let status: String?

    public init(code: Int, message: String, reasons: [String], status: String?) {
        self.code = code
        self.message = message
        self.reasons = reasons
        self.status = status
    }

    /// Parses a Google error body; returns nil when the body is not one.
    init?(body: Data) {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else { return nil }
        let error = envelope.error
        self.init(
            code: error.code,
            message: error.message,
            reasons: error.errors?.compactMap(\.reason) ?? [],
            status: error.status
        )
    }

    private struct Envelope: Decodable {
        let error: Body
    }

    private struct Body: Decodable {
        let code: Int
        let message: String
        let errors: [Item]?
        let status: String?
    }

    private struct Item: Decodable {
        let reason: String?
    }
}
