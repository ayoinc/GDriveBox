import Foundation

/// A Drive file or folder with the fields the sync engine tracks.
public struct DriveFile: Sendable, Equatable, Decodable {
    public static let folderMimeType = "application/vnd.google-apps.folder"
    /// Prefix of Google-native types (Docs, Sheets, Slides, shortcuts, …) that have no binary content.
    public static let googleNativeMimeTypePrefix = "application/vnd.google-apps."
    /// Drive's alias for the root folder of My Drive.
    public static let myDriveRootID = "root"

    /// Partial-response field mask matching the stored properties.
    static let fieldMask = "id,name,mimeType,parents,size,md5Checksum,headRevisionId,version,modifiedTime,trashed,webViewLink"

    public let id: String
    public let name: String
    public let mimeType: String
    public let parents: [String]
    /// Byte size; nil for folders and Google Docs/Sheets/Slides.
    public let size: Int64?
    /// nil for folders and Google-native documents.
    public let md5Checksum: String?
    /// nil for folders and Google-native documents.
    public let headRevisionId: String?
    /// Monotonically increasing; bumps on every server-side change to the file.
    public let version: Int64
    public let modifiedTime: Date
    public let trashed: Bool
    /// The file's page in the Drive web UI; nil when Drive omits it.
    public let webViewLink: URL?

    public var isFolder: Bool { mimeType == Self.folderMimeType }
    /// A Google Doc, Sheet, Slides deck, or other Drive-native item that `alt=media` cannot download.
    public var isGoogleNative: Bool { !isFolder && mimeType.hasPrefix(Self.googleNativeMimeTypePrefix) }

    public init(
        id: String,
        name: String,
        mimeType: String,
        parents: [String],
        size: Int64?,
        md5Checksum: String?,
        headRevisionId: String?,
        version: Int64,
        modifiedTime: Date,
        trashed: Bool,
        webViewLink: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.parents = parents
        self.size = size
        self.md5Checksum = md5Checksum
        self.headRevisionId = headRevisionId
        self.version = version
        self.modifiedTime = modifiedTime
        self.trashed = trashed
        self.webViewLink = webViewLink
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, mimeType, parents, size, md5Checksum, headRevisionId, version, modifiedTime, trashed, webViewLink
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        mimeType = try c.decode(String.self, forKey: .mimeType)
        parents = try c.decodeIfPresent([String].self, forKey: .parents) ?? []
        size = try c.decodeInt64StringIfPresent(forKey: .size)
        md5Checksum = try c.decodeIfPresent(String.self, forKey: .md5Checksum)
        headRevisionId = try c.decodeIfPresent(String.self, forKey: .headRevisionId)
        version = try c.decodeInt64String(forKey: .version)
        modifiedTime = try c.decodeRFC3339Date(forKey: .modifiedTime)
        trashed = try c.decodeIfPresent(Bool.self, forKey: .trashed) ?? false
        webViewLink = try c.decodeIfPresent(URL.self, forKey: .webViewLink)
    }
}

/// One page of `files.list`.
public struct FileListPage: Sendable, Equatable, Decodable {
    public let files: [DriveFile]
    /// nil on the last page.
    public let nextPageToken: String?

    public init(files: [DriveFile], nextPageToken: String?) {
        self.files = files
        self.nextPageToken = nextPageToken
    }

    private enum CodingKeys: String, CodingKey { case files, nextPageToken }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        files = try c.decodeIfPresent([DriveFile].self, forKey: .files) ?? []
        nextPageToken = try c.decodeIfPresent(String.self, forKey: .nextPageToken)
    }
}

/// Filter for `files.list`.
public struct FileListQuery: Sendable, Equatable {
    /// Drive search query (`q` parameter).
    public var q: String?
    /// Drive caps this at 1000.
    public var pageSize: Int

    public init(q: String? = nil, pageSize: Int = 1000) {
        self.q = q
        self.pageSize = pageSize
    }

    /// Non-trashed direct children of a folder. Use `DriveFile.myDriveRootID` for the My Drive root.
    public static func children(of folderID: String) -> FileListQuery {
        FileListQuery(q: "'\(escapeLiteral(folderID))' in parents and trashed = false")
    }

    /// Escapes a value for a single-quoted Drive query string literal.
    static func escapeLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }
}

/// The signed-in user and their storage quota (`about.get`).
public struct About: Sendable, Equatable, Decodable {
    static let fieldMask = "user(displayName,emailAddress),storageQuota(limit,usage)"

    public struct User: Sendable, Equatable, Decodable {
        public let displayName: String
        public let emailAddress: String
    }

    public struct StorageQuota: Sendable, Equatable, Decodable {
        /// nil when the account has unlimited storage.
        public let limit: Int64?
        public let usage: Int64

        private enum CodingKeys: String, CodingKey { case limit, usage }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            limit = try c.decodeInt64StringIfPresent(forKey: .limit)
            usage = try c.decodeInt64String(forKey: .usage)
        }
    }

    public let user: User
    public let storageQuota: StorageQuota
}

// Drive encodes int64 values as JSON strings and timestamps as RFC 3339.
extension KeyedDecodingContainer {
    func decodeInt64String(forKey key: Key) throws -> Int64 {
        let raw = try decode(String.self, forKey: key)
        guard let value = Int64(raw) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected int64 string, got \(raw)")
        }
        return value
    }

    func decodeInt64StringIfPresent(forKey key: Key) throws -> Int64? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decodeInt64String(forKey: key)
    }

    func decodeRFC3339Date(forKey key: Key) throws -> Date {
        let raw = try decode(String.self, forKey: key)
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw) {
            return date
        }
        if let date = try? Date.ISO8601FormatStyle().parse(raw) {
            return date
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected RFC 3339 date, got \(raw)")
    }
}
