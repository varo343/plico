import SwiftUI

/// Product date picker for Planned / Due: quick choices, then a month grid.
/// Keyboard: arrows move the highlighted day, Return picks it, Esc closes.
struct DatePickerPanel: View {
    let title: String
    let explanation: String
    let selected: LocalDay?
    let today: LocalDay
    let change: (LocalDay?) -> Void
    let dismiss: () -> Void

    @State private var month: CalendarMonth
    @State private var highlighted: LocalDay
    @FocusState private var focused: Bool

    private static let itemRadius = SNFloatingSurface<EmptyView>.radius - SNFloatingSurface<EmptyView>.padding
    private let calendar = Calendar.current

    init(title: String, explanation: String, selected: LocalDay?, today: LocalDay,
         change: @escaping (LocalDay?) -> Void, dismiss: @escaping () -> Void) {
        self.title = title
        self.explanation = explanation
        self.selected = selected
        self.today = today
        self.change = change
        self.dismiss = dismiss
        _month = State(initialValue: CalendarMonth(containing: selected ?? today))
        _highlighted = State(initialValue: selected ?? today)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(explanation).font(.system(size: 11)).foregroundStyle(SNColor.textSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)

            quickRow("Today", icon: "sun.max", day: today)
            quickRow("Tomorrow", icon: "sunrise", day: today.adding(days: 1))
            quickRow("Next week", icon: "calendar.badge.clock", day: today.adding(days: 7))
            if selected != nil {
                QuickRow(title: "Clear date", icon: "xmark.circle", trailing: nil, isDestructive: true, radius: Self.itemRadius) {
                    pick(nil)
                }
            }

            Rectangle().fill(SNColor.borderSubtle).frame(height: 1).padding(.horizontal, 4).padding(.vertical, 4)

            monthHeader
            weekdayHeader
            grid
        }
        // No extra padding: items sit at the surface's padding, so radius 8 is
        // concentric with the surface's 12.
        .frame(width: 260)
        .foregroundStyle(SNColor.textPrimary)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.leftArrow) { move(-1); return .handled }
        .onKeyPress(.rightArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-7); return .handled }
        .onKeyPress(.downArrow) { move(7); return .handled }
        .onKeyPress(.return) { pick(highlighted); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private func quickRow(_ title: String, icon: String, day: LocalDay) -> some View {
        QuickRow(title: title, icon: icon,
                 trailing: day.startDate(in: calendar).formatted(.dateTime.weekday(.abbreviated).day()),
                 isChecked: selected == day, radius: Self.itemRadius) {
            pick(day)
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 2) {
            Text(month.title(calendar: calendar))
                .font(.system(size: 13, weight: .semibold))
                .padding(.leading, 8)
            Spacer()
            Button { month = month.adding(months: -1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(SNIconButtonStyle(shape: .rounded(Self.itemRadius)))
            .accessibilityLabel("Previous month")
            Button { month = CalendarMonth(containing: today); highlighted = today } label: {
                Circle().frame(width: 6, height: 6)
            }
            .buttonStyle(SNIconButtonStyle(shape: .rounded(Self.itemRadius)))
            .hoverLabel("This month")
            .accessibilityLabel("This month")
            Button { month = month.adding(months: 1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(SNIconButtonStyle(shape: .rounded(Self.itemRadius)))
            .accessibilityLabel("Next month")
        }
        .padding(.bottom, 2)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(CalendarMonth.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(SNColor.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 2)
        .accessibilityHidden(true)
    }

    private var grid: some View {
        let days = month.gridDays(calendar: calendar)
        return VStack(spacing: 2) {
            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: 2) {
                    ForEach(days[(week * 7)..<(week * 7 + 7)], id: \.self) { day in
                        DayCell(
                            day: day,
                            isInMonth: day.month == month.month,
                            isToday: day == today,
                            isSelected: day == selected,
                            isHighlighted: day == highlighted && focused,
                            radius: Self.itemRadius
                        ) { pick(day) }
                    }
                }
            }
        }
    }

    private func move(_ days: Int) {
        highlighted = highlighted.adding(days: days)
        if CalendarMonth(containing: highlighted) != month { month = CalendarMonth(containing: highlighted) }
    }

    private func pick(_ day: LocalDay?) {
        change(day)
        dismiss()
    }
}

private struct QuickRow: View {
    let title: String
    let icon: String
    let trailing: String?
    var isChecked = false
    var isDestructive = false
    let radius: CGFloat
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SNSpacing.xs) {
                Image(systemName: icon).font(.system(size: 12)).frame(width: 18)
                    .iconMotion(for: icon, on: isHovered)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                if let trailing {
                    Text(trailing).font(.system(size: 11.5)).foregroundStyle(SNColor.textSecondary)
                }
                if isChecked {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(isDestructive ? Color(nsColor: .systemRed) : SNColor.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHovered ? SNColor.borderSubtle.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: radius))
            .contentShape(RoundedRectangle(cornerRadius: radius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct DayCell: View {
    let day: LocalDay
    let isInMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let isHighlighted: Bool
    let radius: CGFloat
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text("\(day.day)")
                .font(.system(size: 12.5, weight: isToday || isSelected ? .bold : .regular).monospacedDigit())
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(background, in: RoundedRectangle(cornerRadius: radius))
                .overlay {
                    if isHighlighted && !isSelected {
                        RoundedRectangle(cornerRadius: radius).strokeBorder(SNColor.focusRing.opacity(0.7), lineWidth: 1.5)
                    }
                }
                .overlay(alignment: .bottom) {
                    if isToday && !isSelected {
                        Circle().fill(SNColor.focusRing).frame(width: 4, height: 4).padding(.bottom, 3)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: radius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(day.startDate().formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        if isSelected { return SNColor.card }
        if isToday { return SNColor.focusRing }
        return isInMonth ? SNColor.textPrimary : SNColor.textSecondary.opacity(0.55)
    }

    private var background: Color {
        if isSelected { return SNColor.textPrimary }
        if isHovered { return SNColor.borderSubtle.opacity(0.7) }
        return .clear
    }
}
