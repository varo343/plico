import SwiftUI

/// The product's tag: text on a hand-drawn tinted shape, slightly tilted.
/// Meaning is carried by the words ("High", "Due today", "Overdue…"), never color alone.
struct SNBadge: View {
    enum Tone: Int {
        case neutral, mint, sun, coral

        var fill: Color {
            switch self {
            case .neutral: SNColor.borderSubtle.opacity(0.75)
            case .mint: SNColor.accentMint
            case .sun: SNColor.accentSun
            case .coral: SNColor.accentCoral
            }
        }

        /// Fixed tilt per tone: playful but stable.
        var tilt: Double {
            switch self {
            case .neutral: 0.8
            case .mint: -1.2
            case .sun: 1.1
            case .coral: -0.9
            }
        }
    }

    enum Size { case regular, small }

    let text: String
    var tone: Tone = .neutral
    var size: Size = .regular

    var body: some View {
        Text(text)
            .font(.system(size: size == .small ? 10.5 : 11.5, weight: .bold, design: .rounded))
            .foregroundStyle(tone == .neutral ? SNColor.textSecondary : SNColor.textPrimary)
            .padding(.horizontal, size == .small ? 7 : 9)
            .padding(.vertical, size == .small ? 2 : 3.5)
            .background(WobblyCapsuleShape(variant: tone.rawValue, amplitude: 2.2).fill(tone.fill))
            .rotationEffect(.degrees(tone.tilt))
            .fixedSize()
            .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

/// Priority tag. Nothing is shown for `.none`.
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
        case .low: SNBadge(text: "Low", tone: .mint, size: size).accessibilityLabel("Priority low")
        case .medium: SNBadge(text: "Medium", tone: .sun, size: size).accessibilityLabel("Priority medium")
        case .high: SNBadge(text: "High", tone: .coral, size: size).accessibilityLabel("Priority high")
        }
    }
}

/// Planned or due date tag. Without icons the words say which date it is.
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
        let lower = day == today || day == today.adding(days: 1) || day == today.adding(days: -1) ? label.lowercased() : label
        switch kind {
        case .planned:
            SNBadge(text: "Planned \(lower)", tone: .neutral, size: size)
        case .due where day < today:
            SNBadge(text: "Overdue · \(label)", tone: .coral, size: size)
        case .due where day == today:
            SNBadge(text: "Due today", tone: .sun, size: size)
        case .due:
            SNBadge(text: "Due \(lower)", tone: .neutral, size: size)
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

