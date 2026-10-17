import Foundation
import Security

/// OAuth tokens. Kept only in the Keychain: never in SwiftData, settings or logs.
public struct OAuthTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Treat tokens as expired a minute early to avoid racing the expiry.
    public func isExpired(now: Date = .now) -> Bool {
        now.addingTimeInterval(60) >= expiresAt
    }
}

public protocol TokenStore: Sendable {
    func load(account: String) throws -> OAuthTokens?
    func save(_ tokens: OAuthTokens, account: String) throws
    func delete(account: String) throws
}

public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}

/// Generic-password Keychain items, readable only by this app, only after the
/// Mac has been unlocked once since boot, and never synced to other devices.
public struct KeychainTokenStore: TokenStore {
    private let service: String

    public init(service: String = "local.smartnotes.outlook") {
        self.service = service
    }

    public func load(account: String) throws -> OAuthTokens? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError.unexpectedStatus(status) }
        return try JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    public func save(_ tokens: OAuthTokens, account: String) throws {
        let data = try JSONEncoder().encode(tokens)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(account: account)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unexpectedStatus(status) }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// In-memory store for tests and sample mode.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private var items: [String: OAuthTokens] = [:]
    private let lock = NSLock()

    public init() {}

    public func load(account: String) throws -> OAuthTokens? {
        lock.withLock { items[account] }
    }

    public func save(_ tokens: OAuthTokens, account: String) throws {
        lock.withLock { items[account] = tokens }
    }

    public func delete(account: String) throws {
        _ = lock.withLock { items.removeValue(forKey: account) }
    }
}
