import Foundation

/// Exponential backoff with full jitter for throttled and transient Drive responses.
public struct RetryPolicy: Sendable, Equatable {
    public var maxRetries: Int
    public var baseDelay: Duration
    public var maxDelay: Duration

    public init(maxRetries: Int = 5, baseDelay: Duration = .seconds(1), maxDelay: Duration = .seconds(32)) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    /// Delay before retry number `attempt` (0-based). A server-provided `Retry-After` wins;
    /// otherwise a uniformly random delay in `[0, min(maxDelay, baseDelay * 2^attempt)]`.
    /// `unitRandom` must be in `[0, 1)`.
    func delay(forRetry attempt: Int, retryAfter: Duration?, unitRandom: Double) -> Duration {
        if let retryAfter { return retryAfter }
        let exponential = baseDelay * (1 << min(attempt, 30))
        let ceiling = min(exponential, maxDelay)
        return ceiling * unitRandom
    }

    /// Google's documented throttling and transient failures.
    static func isRetryable(status: Int, error: GoogleAPIError?) -> Bool {
        switch status {
        case 429, 500, 502, 503, 504:
            return true
        case 403:
            let reasons = error?.reasons ?? []
            return reasons.contains("rateLimitExceeded") || reasons.contains("userRateLimitExceeded")
        default:
            return false
        }
    }

    /// `Retry-After` in delta-seconds form; HTTP-date values fall back to backoff.
    static func retryAfter(from response: HTTPURLResponse) -> Duration? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = Int(value.trimmingCharacters(in: .whitespaces)),
              seconds >= 0
        else { return nil }
        return .seconds(seconds)
    }
}
