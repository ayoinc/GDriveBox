import DriveAPI
import FileProvider
import UniformTypeIdentifiers

/// How a Drive file or folder appears in the GDriveBox domain. Read-only for now: Finder can list,
/// open (download on demand), and evict, but not create, edit, rename, move, or delete. Immutable.
final class FileProviderItem: NSObject, NSFileProviderItem, Sendable {
    let file: DriveFile
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier

    /// - Parameter myDriveRootID: the real ID of the My Drive root, which maps to `.rootContainer`.
    init(file: DriveFile, myDriveRootID: String) {
        self.file = file
        itemIdentifier = Self.identifier(forDriveID: file.id, myDriveRootID: myDriveRootID)
        if itemIdentifier == .rootContainer {
            parentItemIdentifier = .rootContainer
        } else {
            // Files shared into several folders report one parent; Finder shows the first.
            parentItemIdentifier = Self.identifier(forDriveID: file.parents.first ?? myDriveRootID, myDriveRootID: myDriveRootID)
        }
    }

    static func identifier(forDriveID id: String, myDriveRootID: String) -> NSFileProviderItemIdentifier {
        id == myDriveRootID ? .rootContainer : NSFileProviderItemIdentifier(id)
    }

    /// The Drive ID to query for an identifier the system hands back.
    static func driveID(for identifier: NSFileProviderItemIdentifier) -> String {
        identifier == .rootContainer ? DriveFile.myDriveRootID : identifier.rawValue
    }

    /// Drive allows "/" in names, POSIX does not; ":" on disk is what Finder displays as "/".
    /// Google-native documents become `.webloc` links that open the document in the browser.
    var filename: String {
        let name = file.name.replacingOccurrences(of: "/", with: ":")
        return file.isGoogleNative ? name + ".webloc" : name
    }

    var contentType: UTType {
        if file.isFolder { return .folder }
        if file.isGoogleNative { return UTType(filenameExtension: "webloc") ?? .data }
        let pathExtension = (file.name as NSString).pathExtension
        if !pathExtension.isEmpty, let type = UTType(filenameExtension: pathExtension) { return type }
        return UTType(mimeType: file.mimeType) ?? .data
    }

    var documentSize: NSNumber? {
        if file.isFolder { return nil }
        if let webLocation = webLocationDocument { return NSNumber(value: webLocation.count) }
        return file.size.map { NSNumber(value: $0) }
    }

    var capabilities: NSFileProviderItemCapabilities {
        file.isFolder ? [.allowsReading, .allowsContentEnumerating] : [.allowsReading]
    }

    var itemVersion: NSFileProviderItemVersion {
        let content: String
        if file.isFolder {
            content = "folder"
        } else if file.isGoogleNative {
            content = "webloc:\(webLocationURL.absoluteString)"
        } else {
            content = file.md5Checksum ?? file.headRevisionId ?? "v\(file.version)"
        }
        return NSFileProviderItemVersion(contentVersion: Data(content.utf8), metadataVersion: Data("v\(file.version)".utf8))
    }

    var contentModificationDate: Date? { file.modifiedTime }

    /// The bytes `fetchContents` serves for a Google-native document; nil for everything else.
    var webLocationDocument: Data? {
        guard file.isGoogleNative else { return nil }
        // XML property lists serialize deterministically, so the size reported above matches.
        return try? PropertyListSerialization.data(
            fromPropertyList: ["URL": webLocationURL.absoluteString],
            format: .xml,
            options: 0
        )
    }

    private var webLocationURL: URL {
        file.webViewLink ?? URL(string: "https://drive.google.com/open?id=\(file.id)")!
    }
}
