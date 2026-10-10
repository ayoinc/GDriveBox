import DriveAuth

/// Identifiers the app and its File Provider extension must agree on.
public enum SharedConfiguration {
    /// App group; also the keychain access group both bundles are entitled to.
    public static let appGroup = "group.io.github.ayoinc.GDriveBox"

    /// The keychain item holding the archived Google auth state. The app writes it at sign-in and
    /// deletes it at sign-out; the extension reads it (and saves refreshed tokens).
    public static func tokenStore() -> KeychainTokenStore {
        KeychainTokenStore(service: "io.github.ayoinc.GDriveBox", account: "google", accessGroup: appGroup)
    }
}
