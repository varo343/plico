import SwiftUI

/// The product's badge: soft tinted capsule. Meaning is always carried by
/// icon + text, never color alone.
struct SNBadge: View {
    enum Tone {
        case neutral, mint, sun, coral

        var fill: Color {
            switch self {
            case .neutral: SNColor.card
            case .mint: SNColor.accentMint
            case .sun: SNColor.accentSun
            case .coral: SNColor.accentCoral
            }
        }
    }

    enum Size { case regular, small }

    let text: String
    let icon: String
    var tone: Tone = .neutral
    var size: Size = .regular

    var body: some View {
        let isTinted = tone != .neutral
        HStack(spacing: size == .small ? 3 : 4) {
            Image(systemName: icon).font(.system(size: size == .small ? 8.5 : 9.5, weight: .bold))
            Text(text)
        }
        .font(.system(size: size == .small ? 10.5 : 11.5, weight: .semibold))
        .foregroundStyle(isTinted ? SNColor.textPrimary : SNColor.textSecondary)
        .padding(.horizontal, size == .small ? 6 : 8)
        .padding(.vertical, size == .small ? 1.5 : 3)
        .background(tone.fill, in: Capsule())
        .overlay {
            if !isTinted { Capsule().strokeBorder(SNColor.borderSubtle, lineWidth: 1) }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// Priority badge. Nothing is shown for `.none`.
public struct PriorityBadge: View {
    private let priority: Priority
    private let size: SNBadge.Size

    public init(_ priority: Priority) {
        self.init(priority, size: .regular)
    }

    init(_ priority: Priority, size: SNBadge.Size) {
        self.priority = priority
        self.size = size
    }

    public var body: some View {
        switch priority {
        case .none: EmptyView()
        case .low: SNBadge(text: "Low", icon: "arrow.down", tone: .mint, size: size).accessibilityLabel("Priority low")
        case .medium: SNBadge(text: "Medium", icon: "exclamationmark", tone: .sun, size: size).accessibilityLabel("Priority medium")
        case .high: SNBadge(text: "High", icon: "exclamationmark.2", tone: .coral, size: size).accessibilityLabel("Priority high")
        }
    }
}

/// Planned or due date badge. Overdue is spelled out, never only colored.
public struct DateMetadataChip: View {
    public enum Kind {
        case planned, due
    }

    private let kind: Kind
    private let day: LocalDay
    private let today: LocalDay
    private let size: SNBadge.Size

    public init(_ kind: Kind, day: LocalDay, today: LocalDay = .today()) {
        self.init(kind, day: day, today: today, size: .regular)
    }

    init(_ kind: Kind, day: LocalDay, today: LocalDay, size: SNBadge.Size) {
        self.kind = kind
        self.day = day
        self.today = today
        self.size = size
    }

    public var body: some View {
        let label = day.relativeLabel(today: today)
        switch kind {
        case .planned:
            SNBadge(text: label, icon: "calendar", tone: .neutral, size: size)
                .accessibilityLabel("Planned \(label)")
        case .due where day < today:
            SNBadge(text: "Overdue · \(label)", icon: "exclamationmark.circle", tone: .coral, size: size)
                .accessibilityLabel("Overdue, was due \(label)")
        case .due where day == today:
            SNBadge(text: "Due today", icon: "flag", tone: .sun, size: size)
                .accessibilityLabel("Due today")
        case .due:
            SNBadge(text: "Due \(label)", icon: "flag", tone: .neutral, size: size)
                .accessibilityLabel("Due \(label)")
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

