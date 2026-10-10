import FileProvider

/// Remote changes are not tracked yet (S-10 polls Drive's changes feed), so every enumerator reports
/// one fixed anchor and no changes: a folder shows what Drive held when it was first listed.
private let fixedSyncAnchor = NSFileProviderSyncAnchor(Data("read-only-1".utf8))

/// Lists one folder's children page by page; a page is a Drive `nextPageToken`.
final class FolderEnumerator: NSObject, NSFileProviderEnumerator {
    private let container: NSFileProviderItemIdentifier
    private let service: DriveService

    init(container: NSFileProviderItemIdentifier, service: DriveService) {
        self.container = container
        self.service = service
    }

    func invalidate() {}

    func enumerateItems(for observer: any NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        let observer = UncheckedSendable(observer)
        let pageToken = Self.pageToken(from: page)
        Task { [container, service] in
            do {
                let (items, nextPageToken) = try await service.children(of: container, pageToken: pageToken)
                observer.value.didEnumerate(items)
                observer.value.finishEnumerating(upTo: nextPageToken.map { NSFileProviderPage(Data($0.utf8)) })
            } catch {
                FileProviderExtension.logger.error("Enumerating \(container.rawValue, privacy: .public) failed: \(error, privacy: .public)")
                observer.value.finishEnumeratingWithError(error)
            }
        }
    }

    func enumerateChanges(for observer: any NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
        observer.finishEnumeratingChanges(upTo: fixedSyncAnchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(fixedSyncAnchor)
    }

    /// nil for the system's initial pages, otherwise the Drive token this enumerator handed out.
    static func pageToken(from page: NSFileProviderPage) -> String? {
        let initialPages = [NSFileProviderPage.initialPageSortedByName, NSFileProviderPage.initialPageSortedByDate].map { $0 as Data }
        if initialPages.contains(page.rawValue) {
            return nil
        }
        return String(data: page.rawValue, encoding: .utf8)
    }
}

/// Nothing is tracked outside folder enumeration yet.
final class WorkingSetEnumerator: NSObject, NSFileProviderEnumerator {
    func invalidate() {}

    func enumerateItems(for observer: any NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        observer.finishEnumerating(upTo: nil)
    }

    func enumerateChanges(for observer: any NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
        observer.finishEnumeratingChanges(upTo: fixedSyncAnchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(fixedSyncAnchor)
    }
}
