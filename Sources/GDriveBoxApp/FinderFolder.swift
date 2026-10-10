import FileProvider

/// The File Provider domain that puts Google Drive in ~/Library/CloudStorage and the Finder
/// sidebar. One account at a time, so the identifier is fixed.
enum FinderFolder {
    private static let identifier = NSFileProviderDomainIdentifier("google")

    private static var domain: NSFileProviderDomain {
        NSFileProviderDomain(identifier: identifier, displayName: "GDriveBox")
    }

    /// Adds the domain (a no-op when it exists) and tells an extension that reported
    /// `notAuthenticated` that a sign-in is now available. Returns false while the user has not
    /// turned GDriveBox on in System Settings, which macOS requires before the folder syncs.
    static func register() async throws -> Bool {
        let domain = domain
        try await NSFileProviderManager.add(domain)
        try await NSFileProviderManager(for: domain)?.signalErrorResolved(NSFileProviderError(.notAuthenticated))
        return try await isEnabledByUser()
    }

    static func isEnabledByUser() async throws -> Bool {
        try await NSFileProviderManager.domains().contains { $0.identifier == identifier && $0.userEnabled }
    }

    /// System Settings › General › Login Items & Extensions, where File Provider extensions are turned on.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!

    /// Removes the domain together with its local file list and every downloaded copy.
    static func remove() async throws {
        for existing in try await NSFileProviderManager.domains() where existing.identifier == identifier {
            _ = try await NSFileProviderManager.remove(existing, mode: .removeAll)
        }
    }
}
