import Foundation

/// User-assigned priority. Never inferred automatically.
public enum Priority: String, Codable, CaseIterable, Sendable, Comparable {
    case none, low, medium, high

    /// Higher value = more important. Used for sorting.
    public var weight: Int {
        switch self {
        case .none: 0
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }

    public var label: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.weight < rhs.weight }
}

/// Logical block kinds. A block is a paragraph/heading/list item, never a visual line.
public enum BlockType: String, Codable, CaseIterable, Sendable {
    case paragraph
    case heading1
    case heading2
    case heading3
    case bulletItem
    case numberedItem
    case checklistItem
    case quote

    public var isListLike: Bool {
        switch self {
        case .bulletItem, .numberedItem, .checklistItem: true
        default: false
        }
    }

    /// Only list-like blocks can be indented (Tab / Shift+Tab).
    public var supportsIndent: Bool { isListLike }
}

/// Note list sort options. Manual is the only mode that allows drag reordering.
public enum NoteSortMode: String, Codable, CaseIterable, Sendable {
    case manual, updated, created, title, priority, dueDate

    public var label: String {
        switch self {
        case .manual: "Manual"
        case .updated: "Date Updated"
        case .created: "Date Created"
        case .title: "Title"
        case .priority: "Priority"
        case .dueDate: "Due Date"
        }
    }

    public var symbol: String {
        switch self {
        case .manual: "hand.draw"
        case .updated: "clock.arrow.circlepath"
        case .created: "sparkles"
        case .title: "textformat"
        case .priority: "exclamationmark.2"
        case .dueDate: "flag"
        }
    }
}

/// Which notes a query targets. Notes are either active or in Trash (no Archive).
public enum NoteScope: Sendable {
    case active
    case trashed
}
