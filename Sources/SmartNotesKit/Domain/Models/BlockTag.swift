import Foundation

/// A label on one block ("High", "Medium", "Low" or a custom word), so the
/// importance of each list item reads at a glance.
public enum BlockTag: Hashable, Sendable {
    /// Never `.none`; a block without a tag has `tag == nil`.
    case priority(Priority)
    case custom(String)

    public static let maxCustomLength = 24

    /// Trimmed, length-limited custom tag; nil when nothing is left.
    /// "high", "medium" and "low" (any case) become the matching priority tag.
    public static func named(_ name: String) -> BlockTag? {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxCustomLength))
        guard !trimmed.isEmpty else { return nil }
        if let priority = Priority(rawValue: trimmed.lowercased()), priority != .none { return .priority(priority) }
        return .custom(trimmed)
    }

    public var label: String {
        switch self {
        case .priority(let priority): priority.label
        case .custom(let name): name
        }
    }

    /// Stable string form used on disk, in exports and on the pasteboard:
    /// "priority:high" or "custom:Design".
    public var storageValue: String {
        switch self {
        case .priority(let priority): "priority:" + priority.rawValue
        case .custom(let name): "custom:" + name
        }
    }

    /// Unknown or malformed values decode to nil, so the block keeps its text.
    public init?(storageValue: String) {
        if storageValue.hasPrefix("priority:") {
            guard let priority = Priority(rawValue: String(storageValue.dropFirst("priority:".count))), priority != .none else { return nil }
            self = .priority(priority)
        } else if storageValue.hasPrefix("custom:") {
            guard case .custom(let name)? = BlockTag.named(String(storageValue.dropFirst("custom:".count))) else { return nil }
            self = .custom(name)
        } else {
            return nil
        }
    }
}

extension BlockTag: Codable {
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let tag = BlockTag(storageValue: value) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown block tag"))
        }
        self = tag
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageValue)
    }
}
