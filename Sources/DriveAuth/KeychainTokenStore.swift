import Foundation
import Security

/// Persists the archived auth state.
public protocol TokenStore: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
    func delete() throws
}

/// Generic-password keychain item. The app and its File Provider extension share it through
/// `accessGroup`, which requires the data-protection keychain and a signed binary with the
/// matching `keychain-access-groups` entitlement.
public struct KeychainTokenStore: TokenStore {
    public let service: String
    public let account: String
    public let accessGroup: String?
    public let useDataProtectionKeychain: Bool

    public init(service: String, account: String, accessGroup: String? = nil, useDataProtectionKeychain: Bool = true) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
        self.useDataProtectionKeychain = useDataProtectionKeychain
    }

    public func load() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw AuthError.keychain(status)
        }
    }

    public func save(_ data: Data) throws {
        // Readable by the background extension after the first unlock; never migrates off this Mac.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw AuthError.keychain(updateStatus) }

        let addStatus = SecItemAdd(baseQuery.merging(attributes) { $1 } as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw AuthError.keychain(addStatus) }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AuthError.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if useDataProtectionKeychain { query[kSecUseDataProtectionKeychain as String] = true }
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}
