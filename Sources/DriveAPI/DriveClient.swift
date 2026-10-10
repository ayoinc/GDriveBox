import Foundation

/// Typed client for the Google Drive v3 REST endpoints GDriveBox uses.
public struct DriveClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://www.googleapis.com/drive/v3/")!

    private let tokens: any AccessTokenProvider
    private let transport: any HTTPTransport
    private let baseURL: URL
    private let retryPolicy: RetryPolicy
    private let sleep: @Sendable (Duration) async throws -> Void
    private let random: @Sendable () -> Double

    public init(
        tokens: any AccessTokenProvider,
        transport: any HTTPTransport = URLSessionTransport(),
        baseURL: URL = DriveClient.defaultBaseURL,
        retryPolicy: RetryPolicy = RetryPolicy(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.tokens = tokens
        self.transport = transport
        self.baseURL = baseURL
        self.retryPolicy = retryPolicy
        self.sleep = sleep
        self.random = random
    }

    /// The signed-in user and storage quota.
    public func about() async throws -> About {
        try await get("about", query: [URLQueryItem(name: "fields", value: About.fieldMask)])
    }

    /// One page of `files.list`. Pass the previous page's `nextPageToken` to continue.
    public func listFiles(_ query: FileListQuery, pageToken: String? = nil) async throws -> FileListPage {
        var items = [
            URLQueryItem(name: "fields", value: "nextPageToken,files(\(DriveFile.fieldMask))"),
            URLQueryItem(name: "pageSize", value: String(query.pageSize)),
            URLQueryItem(name: "spaces", value: "drive"),
        ]
        if let q = query.q { items.append(URLQueryItem(name: "q", value: q)) }
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        return try await get("files", query: items)
    }

    /// Metadata of one file or folder (`files.get`). `DriveFile.myDriveRootID` returns the My Drive
    /// root with its real ID.
    public func file(id: String) async throws -> DriveFile {
        try await get("files/\(id)", query: [URLQueryItem(name: "fields", value: DriveFile.fieldMask)])
    }

    /// Downloads a file's bytes (`files.get?alt=media`) into a new temporary file the caller owns.
    /// Google-native documents have no bytes; Drive rejects them with 403 `fileNotDownloadable`.
    public func download(fileID: String) async throws -> URL {
        let url = try makeURL(path: "files/\(fileID)", query: [URLQueryItem(name: "alt", value: "media")])
        return try await send(url, accept: nil, using: transport.download) { file in
            defer { try? FileManager.default.removeItem(at: file) }
            return (try? Data(contentsOf: file)) ?? Data()
        }
    }

    /// Every file matching `query`, fetching pages lazily. Cancelling iteration stops fetching.
    public func allFiles(_ query: FileListQuery) -> AsyncThrowingStream<DriveFile, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var pageToken: String?
                    repeat {
                        let page = try await listFiles(query, pageToken: pageToken)
                        for file in page.files { continuation.yield(file) }
                        pageToken = page.nextPageToken
                    } while pageToken != nil
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func get<Response: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> Response {
        let url = try makeURL(path: path, query: query)
        let data = try await send(url, accept: "application/json", using: transport.send) { $0 }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw DriveError.decoding(String(describing: error))
        }
    }

    /// Sends an authorized GET through `exchange`, refreshing the token once on 401 and backing off
    /// on retryable failures. `discardFailure` turns a failed response's body into bytes for error
    /// parsing and releases whatever the body holds.
    private func send<Body>(
        _ url: URL,
        accept: String?,
        using exchange: (URLRequest) async throws -> (Body, HTTPURLResponse),
        discardFailure: (Body) -> Data
    ) async throws -> Body {
        var forceRefresh = false
        var refreshedAfterUnauthorized = false
        var retries = 0

        while true {
            let token = try await tokens.accessToken(forceRefresh: forceRefresh)
            forceRefresh = false

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }

            let (body, response) = try await exchange(request)
            let status = response.statusCode

            if (200..<300).contains(status) { return body }

            let apiError = GoogleAPIError(body: discardFailure(body))

            if status == 401 {
                guard !refreshedAfterUnauthorized else { throw DriveError.unauthorized(apiError) }
                refreshedAfterUnauthorized = true
                forceRefresh = true
                continue
            }

            guard RetryPolicy.isRetryable(status: status, error: apiError), retries < retryPolicy.maxRetries else {
                throw DriveError.http(status: status, error: apiError)
            }
            let delay = retryPolicy.delay(
                forRetry: retries,
                retryAfter: RetryPolicy.retryAfter(from: response),
                unitRandom: random()
            )
            retries += 1
            try await sleep(delay)
        }
    }

    private func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        // URLComponents leaves '+' unescaped, which servers decode as a space; encode it explicitly.
        components.percentEncodedQuery = query
            .map { "\(Self.encode($0.name))=\(Self.encode($0.value ?? ""))" }
            .joined(separator: "&")
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "+&=?")
        return set
    }()

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? value
    }
}
