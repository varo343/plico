import Foundation

public enum ExternalProvider: String, Codable, CaseIterable, Sendable {
    case outlook
}

/// Read-only item imported from an external source (an Outlook message).
/// Not a `Note`: the user explicitly creates a note from it.
public struct ExternalItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var provider: ExternalProvider
    public var accountId: String
    /// Provider ID; immutable Graph IDs preferred.
    public var externalId: String
    public var internetMessageId: String?
    public var subject: String
    public var senderName: String?
    public var senderAddress: String?
    public var preview: String
    public var receivedAt: Date
    public var webUrl: URL?
    public var isDismissedLocally: Bool
    public var isSeenLocally: Bool
    /// Which rule matched, e.g. "flagged". Shown so users know why it appeared.
    public var importRule: String
    public var lastSyncedAt: Date

    public init(
        id: UUID = UUID(), provider: ExternalProvider, accountId: String, externalId: String,
        internetMessageId: String? = nil, subject: String, senderName: String? = nil,
        senderAddress: String? = nil, preview: String, receivedAt: Date, webUrl: URL? = nil,
        isDismissedLocally: Bool = false, isSeenLocally: Bool = false, importRule: String,
        lastSyncedAt: Date
    ) {
        self.id = id
        self.provider = provider
        self.accountId = accountId
        self.externalId = externalId
        self.internetMessageId = internetMessageId
        self.subject = subject
        self.senderName = senderName
        self.senderAddress = senderAddress
        self.preview = preview
        self.receivedAt = receivedAt
        self.webUrl = webUrl
        self.isDismissedLocally = isDismissedLocally
        self.isSeenLocally = isSeenLocally
        self.importRule = importRule
        self.lastSyncedAt = lastSyncedAt
    }

    public var dedupeKey: ExternalItemKey {
        ExternalItemKey(provider: provider, accountId: accountId, externalId: externalId)
    }
}

/// Unique composite key `(provider, accountId, externalId)`.
public struct ExternalItemKey: Hashable, Sendable {
    public var provider: ExternalProvider
    public var accountId: String
    public var externalId: String

    public init(provider: ExternalProvider, accountId: String, externalId: String) {
        self.provider = provider
        self.accountId = accountId
        self.externalId = externalId
    }

    /// Stable string form used as the persisted unique attribute.
    public var storageKey: String {
        // Length-prefixed so separators inside IDs can't create collisions.
        "\(provider.rawValue)|\(accountId.count):\(accountId)|\(externalId)"
    }
}

/// Remote fields of an item as fetched from the provider. Local-only state
/// (dismissed/seen) is deliberately absent so syncing never overwrites it.
public struct ExternalItemDraft: Hashable, Sendable {
    public var key: ExternalItemKey
    public var internetMessageId: String?
    public var subject: String
    public var senderName: String?
    public var senderAddress: String?
    public var preview: String
    public var receivedAt: Date
    public var webUrl: URL?
    public var importRule: String

    public init(
        key: ExternalItemKey, internetMessageId: String? = nil, subject: String,
        senderName: String? = nil, senderAddress: String? = nil, preview: String,
        receivedAt: Date, webUrl: URL? = nil, importRule: String
    ) {
        self.key = key
        self.internetMessageId = internetMessageId
        self.subject = subject
        self.senderName = senderName
        self.senderAddress = senderAddress
        self.preview = preview
        self.receivedAt = receivedAt
        self.webUrl = webUrl
        self.importRule = importRule
    }
}

public enum SyncStatus: String, Codable, Sendable {
    case idle, syncing, error, reauthRequired
}

/// Sync bookkeeping for one connected account.
public struct IntegrationState: Hashable, Sendable {
    public var provider: ExternalProvider
    public var accountId: String
    public var lastSyncAt: Date?
    /// Sensitive operational metadata; never logged.
    public var deltaLink: String?
    public var syncStatus: SyncStatus
    /// Redacted, user-presentable error. Never contains tokens.
    public var lastError: String?

    public init(
        provider: ExternalProvider, accountId: String, lastSyncAt: Date? = nil,
        deltaLink: String? = nil, syncStatus: SyncStatus = .idle, lastError: String? = nil
    ) {
        self.provider = provider
        self.accountId = accountId
        self.lastSyncAt = lastSyncAt
        self.deltaLink = deltaLink
        self.syncStatus = syncStatus
        self.lastError = lastError
    }
}
