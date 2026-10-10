import Foundation
import Synchronization
import Testing
@testable import DriveAPI

// MARK: - Fakes

private struct Reply {
    var status: Int
    var body: String
    var headers: [String: String] = [:]
}

private final class ScriptedTransport: HTTPTransport {
    private let state: Mutex<(replies: [Reply], requests: [URLRequest])>

    init(_ replies: [Reply]) {
        state = Mutex((replies, []))
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply = state.withLock { state -> Reply? in
            state.requests.append(request)
            return state.replies.isEmpty ? nil : state.replies.removeFirst()
        }
        guard let reply else {
            Issue.record("Unexpected extra request to \(request.url?.absoluteString ?? "?")")
            throw URLError(.resourceUnavailable)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        return (Data(reply.body.utf8), response)
    }
}

private final class CountingTokens: AccessTokenProvider {
    private let calls = Mutex<[Bool]>([])

    var forceRefreshFlags: [Bool] { calls.withLock { $0 } }

    func accessToken(forceRefresh: Bool) async throws -> String {
        calls.withLock { calls in
            calls.append(forceRefresh)
            return "token-\(calls.count)"
        }
    }
}

private final class SleepRecorder: Sendable {
    private let delays = Mutex<[Duration]>([])

    var recorded: [Duration] { delays.withLock { $0 } }

    func record(_ delay: Duration) { delays.withLock { $0.append(delay) } }
}

private func makeClient(
    _ transport: ScriptedTransport,
    tokens: CountingTokens = CountingTokens(),
    sleeps: SleepRecorder = SleepRecorder()
) -> DriveClient {
    DriveClient(tokens: tokens, transport: transport, sleep: { sleeps.record($0) }, random: { 0.5 })
}

private func googleError(_ code: Int, reason: String, status: String) -> String {
    #"{"error":{"code":\#(code),"message":"\#(reason) happened","errors":[{"domain":"global","reason":"\#(reason)","message":"\#(reason) happened"}],"status":"\#(status)"}}"#
}

private let aboutBody = #"{"user":{"displayName":"Ada","emailAddress":"ada@example.com"},"storageQuota":{"limit":"16106127360","usage":"2048"}}"#

private func pageBody(ids: [String], next: String?) -> String {
    let files = ids.map { #"{"id":"\#($0)","name":"\#($0).txt","mimeType":"text/plain","parents":["root"],"size":"1","md5Checksum":"m","headRevisionId":"r","version":"1","modifiedTime":"2026-10-09T08:00:00Z"}"# }
    let token = next.map { #""nextPageToken":"\#($0)","# } ?? ""
    return "{\(token)\"files\":[\(files.joined(separator: ","))]}"
}

private func queryValue(_ name: String, in request: URLRequest) -> String? {
    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
}

// MARK: - Tests

@Test func listFilesDecodesDriveWireFormat() async throws {
    let body = """
    {"nextPageToken":"p2","files":[
      {"id":"f1","name":"Report.pdf","mimeType":"application/pdf","parents":["root"],"size":"10485760",
       "md5Checksum":"abc","headRevisionId":"rev1","version":"42","modifiedTime":"2026-10-10T12:34:56.789Z","trashed":false},
      {"id":"d1","name":"Photos","mimeType":"application/vnd.google-apps.folder","version":"7",
       "modifiedTime":"2026-10-09T08:00:00Z"}
    ]}
    """
    let transport = ScriptedTransport([Reply(status: 200, body: body)])

    let page = try await makeClient(transport).listFiles(.children(of: DriveFile.myDriveRootID), pageToken: "p1")

    #expect(page.nextPageToken == "p2")
    let file = try #require(page.files.first)
    #expect(file.size == 10_485_760)
    #expect(file.version == 42)
    #expect(abs(file.modifiedTime.timeIntervalSince1970 - 1_791_635_696.789) < 0.001)
    #expect(!file.isFolder)

    let folder = try #require(page.files.last)
    #expect(folder.isFolder)
    #expect(folder.parents.isEmpty)
    #expect(folder.size == nil)
    #expect(folder.md5Checksum == nil)
    #expect(folder.trashed == false)
    #expect(folder.modifiedTime.timeIntervalSince1970 == 1_791_532_800)

    let request = try #require(transport.requests.first)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
    #expect(queryValue("q", in: request) == "'root' in parents and trashed = false")
    #expect(queryValue("pageToken", in: request) == "p1")
}

@Test func unauthorizedForcesOneTokenRefreshThenSucceeds() async throws {
    let transport = ScriptedTransport([
        Reply(status: 401, body: googleError(401, reason: "authError", status: "UNAUTHENTICATED")),
        Reply(status: 200, body: aboutBody),
    ])
    let tokens = CountingTokens()
    let sleeps = SleepRecorder()

    let about = try await makeClient(transport, tokens: tokens, sleeps: sleeps).about()

    #expect(about.user.emailAddress == "ada@example.com")
    #expect(about.storageQuota.limit == 16_106_127_360)
    #expect(tokens.forceRefreshFlags == [false, true])
    #expect(transport.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer token-2")
    #expect(sleeps.recorded.isEmpty)
}

@Test func repeatedUnauthorizedThrowsWithoutSecondRefresh() async throws {
    let body = googleError(401, reason: "authError", status: "UNAUTHENTICATED")
    let transport = ScriptedTransport([Reply(status: 401, body: body), Reply(status: 401, body: body)])
    let tokens = CountingTokens()

    await #expect(throws: DriveError.unauthorized(GoogleAPIError(code: 401, message: "authError happened", reasons: ["authError"], status: "UNAUTHENTICATED"))) {
        try await makeClient(transport, tokens: tokens).about()
    }
    #expect(tokens.forceRefreshFlags == [false, true])
    #expect(transport.requests.count == 2)
}

@Test func throttledResponsesBackOffWithJitterAndHonorRetryAfter() async throws {
    let transport = ScriptedTransport([
        Reply(status: 403, body: googleError(403, reason: "userRateLimitExceeded", status: "PERMISSION_DENIED")),
        Reply(status: 429, body: googleError(429, reason: "rateLimitExceeded", status: "RESOURCE_EXHAUSTED"), headers: ["Retry-After": "7"]),
        Reply(status: 503, body: "Service Unavailable"),
        Reply(status: 200, body: aboutBody),
    ])
    let sleeps = SleepRecorder()

    _ = try await makeClient(transport, sleeps: sleeps).about()

    // random() == 0.5: retry 0 → 0.5 × 1 s; retry 1 → Retry-After 7 s; retry 2 → 0.5 × 4 s.
    #expect(sleeps.recorded == [.milliseconds(500), .seconds(7), .seconds(2)])
    #expect(transport.requests.count == 4)
}

@Test func forbiddenWithoutRateLimitReasonFailsImmediately() async throws {
    let transport = ScriptedTransport([
        Reply(status: 403, body: googleError(403, reason: "insufficientFilePermissions", status: "PERMISSION_DENIED")),
    ])
    let sleeps = SleepRecorder()

    await #expect(throws: DriveError.http(status: 403, error: GoogleAPIError(code: 403, message: "insufficientFilePermissions happened", reasons: ["insufficientFilePermissions"], status: "PERMISSION_DENIED"))) {
        try await makeClient(transport, sleeps: sleeps).about()
    }
    #expect(sleeps.recorded.isEmpty)
}

@Test func retriesStopAfterFiveAttempts() async throws {
    let transport = ScriptedTransport(Array(repeating: Reply(status: 500, body: "boom"), count: 6))
    let sleeps = SleepRecorder()

    await #expect(throws: DriveError.http(status: 500, error: nil)) {
        try await makeClient(transport, sleeps: sleeps).about()
    }
    #expect(sleeps.recorded == [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8)])
    #expect(transport.requests.count == 6)
}

@Test func backoffCeilingIsCappedAtMaxDelay() {
    let policy = RetryPolicy()
    // Ceiling for retry 5 is exactly 32 s; for retry 12 it would be 4096 s without the cap.
    #expect(policy.delay(forRetry: 5, retryAfter: nil, unitRandom: 0.999) == .seconds(32) * 0.999)
    #expect(policy.delay(forRetry: 12, retryAfter: nil, unitRandom: 0.999) == .seconds(32) * 0.999)
}

@Test(arguments: [
    (429, nil, true),
    (403, "rateLimitExceeded", true),
    (403, "userRateLimitExceeded", true),
    (500, nil, true),
    (502, nil, true),
    (503, nil, true),
    (504, nil, true),
    (403, "insufficientFilePermissions", false),
    (403, nil, false),
    (400, "badRequest", false),
    (404, "notFound", false),
] as [(Int, String?, Bool)])
func retryableClassification(status: Int, reason: String?, retryable: Bool) {
    let error = reason.map { GoogleAPIError(code: status, message: "", reasons: [$0], status: nil) }
    #expect(RetryPolicy.isRetryable(status: status, error: error) == retryable)
}

@Test func allFilesFollowsPageTokensUntilExhausted() async throws {
    let transport = ScriptedTransport([
        Reply(status: 200, body: pageBody(ids: ["a", "b"], next: "t2")),
        Reply(status: 200, body: pageBody(ids: ["c"], next: nil)),
    ])

    var ids: [String] = []
    for try await file in makeClient(transport).allFiles(.children(of: "root")) {
        ids.append(file.id)
    }

    #expect(ids == ["a", "b", "c"])
    #expect(transport.requests.map { queryValue("pageToken", in: $0) } == [nil, "t2"])
}

@Test func childrenQueryEscapesStringLiterals() {
    #expect(FileListQuery.children(of: #"a'b\c"#).q == #"'a\'b\\c' in parents and trashed = false"#)
}
