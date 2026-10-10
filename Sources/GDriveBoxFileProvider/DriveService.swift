import DriveAPI
import DriveAuth
import FileProvider

/// The extension's view of Google Drive: restores the shared sign-in from the keychain, resolves
/// the My Drive root, and serves metadata, folder pages, and file contents.
actor DriveService {
    private let tokenStore: any TokenStore
    private var client: DriveClient?
    private var myDriveRootID: String?

    init(tokenStore: any TokenStore) {
        self.tokenStore = tokenStore
    }

    func item(for identifier: NSFileProviderItemIdentifier) async throws -> FileProviderItem {
        try await mapErrors {
            let rootID = try await rootID()
            let file = try await drive().file(id: FileProviderItem.driveID(for: identifier))
            // Trashed items have left the domain; the system deletes them locally on noSuchItem.
            guard !file.trashed else { throw NSFileProviderError(.noSuchItem) }
            return FileProviderItem(file: file, myDriveRootID: rootID)
        }
    }

    /// One page of a folder's non-trashed children and the token for the next page.
    func children(
        of container: NSFileProviderItemIdentifier,
        pageToken: String?
    ) async throws -> (items: [FileProviderItem], nextPageToken: String?) {
        try await mapErrors {
            let rootID = try await rootID()
            let page = try await drive().listFiles(
                .children(of: FileProviderItem.driveID(for: container)),
                pageToken: pageToken
            )
            return (page.files.map { FileProviderItem(file: $0, myDriveRootID: rootID) }, page.nextPageToken)
        }
    }

    /// Writes the item's contents to a new file in `directory` and returns it.
    func contents(of item: FileProviderItem, in directory: URL) async throws -> URL {
        try await mapErrors {
            let destination = directory.appending(path: UUID().uuidString)
            if let webLocation = item.webLocationDocument {
                try webLocation.write(to: destination)
                return destination
            }
            let downloaded = try await drive().download(fileID: item.file.id)
            do {
                try FileManager.default.moveItem(at: downloaded, to: destination)
            } catch {
                try? FileManager.default.removeItem(at: downloaded)
                throw error
            }
            return destination
        }
    }

    private func drive() throws -> DriveClient {
        if let client { return client }
        guard let session = try AuthSession.restore(from: tokenStore) else {
            throw NSFileProviderError(.notAuthenticated)
        }
        let client = DriveClient(tokens: session)
        self.client = client
        return client
    }

    private func rootID() async throws -> String {
        if let myDriveRootID { return myDriveRootID }
        let id = try await drive().file(id: DriveFile.myDriveRootID).id
        myDriveRootID = id
        return id
    }

    /// Translates failures into File Provider errors. After an authentication failure the cached
    /// session is dropped, so the next call picks up a fresh sign-in from the keychain.
    private func mapErrors<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            let mapped = FileProviderErrors.map(error)
            if (mapped as? NSFileProviderError)?.code == .notAuthenticated {
                client = nil
                myDriveRootID = nil
            }
            throw mapped
        }
    }
}

enum FileProviderErrors {
    /// The File Provider error the system acts on for a Drive, auth, or network failure.
    static func map(_ error: any Error) -> any Error {
        switch error {
        case is NSFileProviderError:
            return error
        case is CancellationError:
            return CocoaError(.userCancelled)
        case let urlError as URLError where urlError.code == .cancelled:
            return CocoaError(.userCancelled)
        case AuthError.reauthenticationRequired, AuthError.corruptStoredState, AuthError.noAccessToken, DriveError.unauthorized:
            return NSFileProviderError(.notAuthenticated)
        case DriveError.http(status: 404, _):
            return NSFileProviderError(.noSuchItem)
        case DriveError.http(let status, _) where status == 429 || status >= 500:
            return NSFileProviderError(.serverUnreachable)
        default:
            break
        }
        if isNetworkFailure(error as NSError) { return NSFileProviderError(.serverUnreachable) }
        return error
    }

    /// URL-loading failures, also when wrapped (AppAuth reports refresh failures that way).
    private static func isNetworkFailure(_ error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain { return error.code != NSURLErrorCancelled }
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
        return isNetworkFailure(underlying)
    }
}
