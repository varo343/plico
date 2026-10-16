import SwiftUI

/// Priority label: text + icon + color, never color alone.
public struct PriorityBadge: View {
    private let priority: Priority

    public init(_ priority: Priority) {
        self.priority = priority
    }

    public var body: some View {
        if priority != .none {
            Label(priority.label, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SNColor.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(fill, in: Capsule())
                .accessibilityLabel("Priority \(priority.label)")
        }
    }

    private var symbol: String {
        switch priority {
        case .high: "exclamationmark.2"
        case .medium: "exclamationmark"
        default: "arrow.down"
        }
    }

    private var fill: Color {
        switch priority {
        case .high: SNColor.accentCoral
        case .medium: SNColor.borderSubtle
        default: SNColor.accentMint
        }
    }
}

/// Planned or due date chip. Overdue due dates get an explicit "Overdue" label.
public struct DateMetadataChip: View {
    public enum Kind {
        case planned, due
    }

    private let kind: Kind
    private let day: LocalDay
    private let today: LocalDay

    public init(_ kind: Kind, day: LocalDay, today: LocalDay = .today()) {
        self.kind = kind
        self.day = day
        self.today = today
    }

    public var body: some View {
        Label(text, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isOverdue ? SNColor.textPrimary : SNColor.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isOverdue ? SNColor.accentCoral : SNColor.borderSubtle.opacity(0.5), in: Capsule())
    }

    private var isOverdue: Bool { kind == .due && day < today }

    private var text: String {
        let label = day.relativeLabel(today: today)
        switch kind {
        case .planned: return "Planned \(label)"
        case .due: return isOverdue ? "Overdue · \(label)" : "Due \(label)"
        }
    }

    private var symbol: String {
        switch kind {
        case .planned: "calendar"
        case .due: isOverdue ? "exclamationmark.circle" : "flag"
        }
    }
}

extension LocalDay {
    /// "Today", "Tomorrow", "Yesterday", or a short date (year shown only if different).
    public func relativeLabel(today: LocalDay, calendar: Calendar = .current) -> String {
        if self == today { return "Today" }
        if self == today.adding(days: 1) { return "Tomorrow" }
        if self == today.adding(days: -1) { return "Yesterday" }
        let date = startDate(in: calendar)
        let format: Date.FormatStyle = year == today.year
            ? .dateTime.month(.abbreviated).day()
            : .dateTime.month(.abbreviated).day().year()
        return date.formatted(format)
    }
}
