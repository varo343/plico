import SwiftUI

/// Notes the user scheduled: Overdue, Due today, Planned today. Cards open the
/// note; there are no completion toggles here (checklists are done in the editor).
struct TodayView: View {
    @Bindable var today: TodayModel
    let notes: NotesModel
    let showNotes: () -> Void

    var body: some View {
        let sections = today.sections(from: notes.activeNotes)
        VStack(alignment: .leading, spacing: 0) {
            header
            if sections.isEmpty {
                EmptyState(symbol: "sun.max", title: "Nothing scheduled for today",
                           message: "Notes appear here when you give them a planned or due date.") {
                    Button("Go to Notes", action: showNotes)
                        .buttonStyle(SNCapsuleButtonStyle())
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: SNSpacing.l) {
                        ForEach(sections) { section in
                            TodaySectionView(
                                section: section,
                                today: today.today,
                                showsCompleted: today.showsCompletedItems,
                                selectedID: notes.selectedNoteID,
                                open: { notes.select($0) }
                            )
                        }
                    }
                    .padding(SNSpacing.m)
                    .padding(.bottom, SNSpacing.l)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Today").font(SNFont.section).foregroundStyle(SNColor.textPrimary)
            HStack {
                Text(today.today.startDate().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(SNFont.secondary)
                    .foregroundStyle(SNColor.textSecondary)
                Spacer()
                Toggle("Show completed", isOn: $today.showsCompletedItems)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .help("Show checked checklist items on cards")
            }
        }
        .padding(.horizontal, SNSpacing.m)
        .padding(.top, SNSpacing.s)
        .padding(.bottom, SNSpacing.xs)
    }
}

private struct TodaySectionView: View {
    let section: TodaySection
    let today: LocalDay
    let showsCompleted: Bool
    let selectedID: UUID?
    let open: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SNSpacing.xs) {
            HStack(spacing: SNSpacing.xxs) {
                if section.kind == .overdue {
                    Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                }
                Text(section.kind.title)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SNColor.textSecondary)
            .accessibilityAddTraits(.isHeader)

            ForEach(section.items) { item in
                TodayCard(item: item, today: today, showsCompleted: showsCompleted,
                          isSelected: item.id == selectedID) { open(item.id) }
            }
        }
    }
}

private struct TodayCard: View {
    let item: TodayItem
    let today: LocalDay
    let showsCompleted: Bool
    let isSelected: Bool
    let open: () -> Void
    @State private var isHovered = false

    private static let maxLines = 4

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: SNSpacing.xxs) {
                Text(item.summary.displayTitle)
                    .font(SNFont.rowTitle)
                    .foregroundStyle(SNColor.textPrimary)
                    .lineLimit(2)
                FlowLayout {
                    PriorityBadge(item.summary.priority)
                    if let due = item.summary.dueDate { DateMetadataChip(.due, day: due, today: today) }
                    if let planned = item.summary.plannedDate { DateMetadataChip(.planned, day: planned, today: today) }
                }
                checklist
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SNSpacing.s)
            .background(isHovered && !isSelected ? SNColor.borderSubtle.opacity(0.35) : SNColor.card,
                        in: RoundedRectangle(cornerRadius: SNRadius.standard))
            .overlay(
                RoundedRectangle(cornerRadius: SNRadius.standard)
                    .strokeBorder(isSelected ? SNColor.focusRing.opacity(0.6) : SNColor.borderSubtle, lineWidth: 1)
            )
            .shadow(color: .black.opacity(isSelected ? 0.06 : 0), radius: 3, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: SNRadius.standard))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the note")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Read-only preview: open items first; completed ones only when shown.
    @ViewBuilder
    private var checklist: some View {
        let lines = item.checklist.filter { showsCompleted || !$0.isChecked }
        let done = item.checklist.filter(\.isChecked).count
        if !item.checklist.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines.prefix(Self.maxLines)) { line in
                    HStack(alignment: .firstTextBaseline, spacing: SNSpacing.xxs) {
                        Image(systemName: line.isChecked ? "checkmark.square" : "square")
                            .font(.system(size: 11))
                        Text(line.text.isEmpty ? " " : line.text)
                            .strikethrough(line.isChecked)
                            .lineLimit(1)
                    }
                    .foregroundStyle(line.isChecked ? SNColor.textSecondary : SNColor.textPrimary)
                }
                let hidden = lines.count - min(lines.count, Self.maxLines)
                Text(hidden > 0 ? "\(done) of \(item.checklist.count) done · \(hidden) more" : "\(done) of \(item.checklist.count) done")
                    .foregroundStyle(SNColor.textSecondary)
            }
            .font(SNFont.secondary)
            .padding(.top, 2)
        }
    }
}
