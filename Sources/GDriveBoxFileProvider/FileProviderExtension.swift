import DriveAPI
import FileProvider
import GDriveBoxShared
import os

/// The File Provider extension behind the GDriveBox folder in ~/Library/CloudStorage. Items are
/// dataless until opened; `fetchContents` downloads them on demand. Read-only for now.
@objc(GDriveBoxFileProviderExtension)
final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    static let logger = Logger(subsystem: "io.github.ayoinc.GDriveBox.FileProvider", category: "extension")

    private let domain: NSFileProviderDomain
    private let service = DriveService(tokenStore: SharedConfiguration.tokenStore())

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
        Self.logger.info("Started for domain \(domain.identifier.rawValue, privacy: .public)")
    }

    func invalidate() {}

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, (any Error)?) -> Void
    ) -> Progress {
        let completion = UncheckedSendable(completionHandler)
        return run("item(\(identifier.rawValue))") { [service] in
            do {
                completion.value(try await service.item(for: identifier), nil)
            } catch {
                completion.value(nil, error)
            }
        }
    }

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, (any Error)?) -> Void
    ) -> Progress {
        let completion = UncheckedSendable(completionHandler)
        let directory: URL
        do {
            // Same volume as the domain, so the system can take the file without copying.
            directory = try NSFileProviderManager(for: domain)?.temporaryDirectoryURL() ?? FileManager.default.temporaryDirectory
        } catch {
            completionHandler(nil, nil, error)
            return Progress()
        }
        return run("fetchContents(\(itemIdentifier.rawValue))") { [service] in
            do {
                let item = try await service.item(for: itemIdentifier)
                let contents = try await service.contents(of: item, in: directory)
                completion.value(contents, item, nil)
            } catch {
                completion.value(nil, nil, error)
            }
        }
    }

    // MARK: Read-only: the items' capabilities forbid these, so they only arrive in edge cases.

    func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void
    ) -> Progress {
        completionHandler(nil, [], false, CocoaError(.featureUnsupported))
        return Progress()
    }

    func modifyItem(
        _ item: NSFileProviderItem,
        baseVersion version: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void
    ) -> Progress {
        completionHandler(nil, [], false, CocoaError(.featureUnsupported))
        return Progress()
    }

    func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion version: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping ((any Error)?) -> Void
    ) -> Progress {
        // deletionRejected (rather than featureUnsupported) makes the system restore the item locally.
        completionHandler(NSFileProviderError(.deletionRejected))
        return Progress()
    }

    // MARK: Enumeration

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> any NSFileProviderEnumerator {
        switch containerItemIdentifier {
        case .trashContainer:
            throw CocoaError(.featureUnsupported)
        case .workingSet:
            return WorkingSetEnumerator()
        default:
            return FolderEnumerator(container: containerItemIdentifier, service: service)
        }
    }

    /// Runs `work` in a task whose cancellation follows the returned progress.
    private func run(_ operation: String, _ work: @escaping @Sendable () async -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        let task = Task {
            await work()
            progress.completedUnitCount = 1
        }
        progress.cancellationHandler = {
            Self.logger.info("Cancelled \(operation, privacy: .public)")
            task.cancel()
        }
        return progress
    }
}

/// File Provider observers and completion handlers may be called from any thread but are not
/// annotated `Sendable`.
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) { self.value = value }
}
