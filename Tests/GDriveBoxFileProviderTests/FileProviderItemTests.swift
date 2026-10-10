import DriveAPI
import DriveAuth
import FileProvider
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import GDriveBoxFileProvider

private let rootID = "0AAbcRoot"

private func driveFile(
    id: String = "f1",
    name: String = "Report.pdf",
    mimeType: String = "application/pdf",
    parents: [String] = [rootID],
    size: Int64? = 42,
    md5: String? = "md5-1",
    version: Int64 = 7,
    webViewLink: URL? = nil
) -> DriveFile {
    DriveFile(
        id: id, name: name, mimeType: mimeType, parents: parents, size: size, md5Checksum: md5,
        headRevisionId: md5.map { "rev-\($0)" }, version: version,
        modifiedTime: Date(timeIntervalSince1970: 1_791_532_800), trashed: false, webViewLink: webViewLink
    )
}

@Test func myDriveRootMapsToTheRootContainer() {
    let root = FileProviderItem(file: driveFile(id: rootID, name: "My Drive", mimeType: DriveFile.folderMimeType, parents: [], size: nil, md5: nil), myDriveRootID: rootID)
    #expect(root.itemIdentifier == .rootContainer)
    #expect(root.parentItemIdentifier == .rootContainer)
    #expect(FileProviderItem.driveID(for: .rootContainer) == "root")
}

@Test func childrenOfTheRootPointAtTheRootContainer() {
    let item = FileProviderItem(file: driveFile(), myDriveRootID: rootID)
    #expect(item.itemIdentifier == NSFileProviderItemIdentifier("f1"))
    #expect(item.parentItemIdentifier == .rootContainer)

    let nested = FileProviderItem(file: driveFile(id: "f2", parents: ["folderA"]), myDriveRootID: rootID)
    #expect(nested.parentItemIdentifier == NSFileProviderItemIdentifier("folderA"))
    #expect(FileProviderItem.driveID(for: nested.itemIdentifier) == "f2")
}

@Test func regularFilesAreReadOnlyDocumentsWithDriveMetadata() {
    let item = FileProviderItem(file: driveFile(), myDriveRootID: rootID)
    #expect(item.filename == "Report.pdf")
    #expect(item.contentType == .pdf)
    #expect(item.documentSize == 42)
    #expect(item.capabilities == [.allowsReading])
    #expect(item.itemVersion.contentVersion == Data("md5-1".utf8))
    #expect(item.itemVersion.metadataVersion == Data("v7".utf8))
    #expect(item.webLocationDocument == nil)
}

@Test func foldersAllowEnumerationOnly() {
    let folder = FileProviderItem(file: driveFile(id: "d1", name: "Photos", mimeType: DriveFile.folderMimeType, size: nil, md5: nil), myDriveRootID: rootID)
    #expect(folder.contentType == .folder)
    #expect(folder.documentSize == nil)
    #expect(folder.capabilities == [.allowsReading, .allowsContentEnumerating])
}

@Test func slashesInDriveNamesBecomeColonsOnDisk() {
    let item = FileProviderItem(file: driveFile(name: "Q1/Q2 plan.txt", mimeType: "text/plain"), myDriveRootID: rootID)
    #expect(item.filename == "Q1:Q2 plan.txt")
}

@Test func googleDocsBecomeWeblocLinksToTheDocument() throws {
    let link = try #require(URL(string: "https://docs.google.com/document/d/doc1/edit?usp=drivesdk"))
    let item = FileProviderItem(
        file: driveFile(id: "doc1", name: "Plan", mimeType: "application/vnd.google-apps.document", size: nil, md5: nil, webViewLink: link),
        myDriveRootID: rootID
    )

    #expect(item.filename == "Plan.webloc")
    #expect(item.contentType == UTType(filenameExtension: "webloc"))
    let document = try #require(item.webLocationDocument)
    #expect(item.documentSize == NSNumber(value: document.count))
    let plist = try #require(try PropertyListSerialization.propertyList(from: document, format: nil) as? [String: String])
    #expect(plist == ["URL": link.absoluteString])
    // A metadata-only edit to the doc must not invalidate the local link file.
    #expect(item.itemVersion.contentVersion == Data("webloc:\(link.absoluteString)".utf8))
}

@Test func googleDocsWithoutWebViewLinkFallBackToDriveOpenURL() throws {
    let item = FileProviderItem(file: driveFile(id: "sheet1", name: "Budget", mimeType: "application/vnd.google-apps.spreadsheet", size: nil, md5: nil), myDriveRootID: rootID)
    let document = try #require(item.webLocationDocument)
    let plist = try #require(try PropertyListSerialization.propertyList(from: document, format: nil) as? [String: String])
    #expect(plist["URL"] == "https://drive.google.com/open?id=sheet1")
}

@Test func initialPagesHaveNoDriveTokenAndLaterPagesRoundTrip() {
    #expect(FolderEnumerator.pageToken(from: NSFileProviderPage(Data("next-123".utf8))) == "next-123")
    #expect(FolderEnumerator.pageToken(from: NSFileProviderPage(NSFileProviderPage.initialPageSortedByName as Data)) == nil)
    #expect(FolderEnumerator.pageToken(from: NSFileProviderPage(NSFileProviderPage.initialPageSortedByDate as Data)) == nil)
}

@Test(arguments: [
    (AuthError.reauthenticationRequired as any Error, NSFileProviderError.Code.notAuthenticated),
    (DriveError.unauthorized(nil), .notAuthenticated),
    (DriveError.http(status: 404, error: nil), .noSuchItem),
    (DriveError.http(status: 503, error: nil), .serverUnreachable),
    (URLError(.notConnectedToInternet), .serverUnreachable),
] as [(any Error, NSFileProviderError.Code)])
func failuresMapToFileProviderErrors(error: any Error, expected: NSFileProviderError.Code) {
    #expect((FileProviderErrors.map(error) as? NSFileProviderError)?.code == expected)
}

@Test func cancellationMapsToUserCancelled() {
    #expect((FileProviderErrors.map(CancellationError()) as? CocoaError)?.code == .userCancelled)
    #expect((FileProviderErrors.map(DriveError.http(status: 403, error: nil)) as? DriveError) == .http(status: 403, error: nil))
}
