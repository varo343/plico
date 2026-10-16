import SwiftUI

/// Compact, unobtrusive metadata under the title: priority, planned date,
/// due date, pin. Values come from the list (the metadata source of truth) and
/// are saved through the metadata path, never through the editor's autosave.
struct NoteMetadataStrip: View {
    let noteID: UUID
    let notes: NotesModel
    var today: LocalDay = .today()

    var body: some View {
        if let summary = notes.summary(for: noteID) {
            metadata(summary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metadata(_ summary: NoteSummary) -> some View {
        FlowLayout(spacing: SNSpacing.xs) {
            PriorityField(priority: summary.priority) { notes.setPriority($0, for: noteID) }
            DateField(kind: .planned, day: summary.plannedDate, today: today) { notes.setPlannedDate($0, for: noteID) }
            DateField(kind: .due, day: summary.dueDate, today: today) { notes.setDueDate($0, for: noteID) }
            Button { notes.togglePin(noteID) } label: {
                Label(summary.isPinned ? "Pinned" : "Pin", systemImage: summary.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(MetadataButtonStyle(isSet: summary.isPinned))
            .help(summary.isPinned ? "Unpin (⇧⌘P)" : "Pin to the top of the list (⇧⌘P)")
        }
    }
}

/// Priority as a badge with a product dropdown of choices.
private struct PriorityField: View {
    let priority: Priority
    let change: (Priority) -> Void

    var body: some View {
        SNDropdown(minWidth: 170, shape: .capsule, showsChevron: false) {
            [.header("Priority")] + Priority.allCases.map { option in
                .item(SNMenuItem(
                    title: option.label,
                    badge: option == .none ? AnyView(Text("None").font(.system(size: 13, weight: .medium))) : AnyView(PriorityBadge(option)),
                    isChecked: option == priority
                ) { change(option) })
            }
        } label: {
            if priority == .none {
                Label("Priority", systemImage: "flag").labelStyle(.titleAndIcon)
                    .font(.system(size: 12)).foregroundStyle(SNColor.textSecondary)
            } else {
                PriorityBadge(priority)
            }
        }
        .hoverLabel("Priority is only set by you")
        .accessibilityLabel("Priority, \(priority.label)")
    }
}

/// Planned or due date with a calendar panel and quick choices.
private struct DateField: View {
    let kind: DateMetadataChip.Kind
    let day: LocalDay?
    let today: LocalDay
    let change: (LocalDay?) -> Void

    private var title: String { kind == .planned ? "Planned" : "Due" }
    private var explanation: String {
        kind == .planned ? "When you intend to work on this note." : "The deadline for this note."
    }

    var body: some View {
        SNPopoverButton(isSet: day != nil) {
            Group {
                if let day {
                    DateMetadataChip(kind, day: day, today: today)
                } else {
                    Label(title, systemImage: kind == .planned ? "calendar" : "flag.checkered")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12))
                        .foregroundStyle(SNColor.textSecondary)
                }
            }
            .padding(.horizontal, 6)
        } panel: { dismiss in
            DatePickerPanel(title: "\(title) date", explanation: explanation, selected: day, today: today,
                            change: change, dismiss: dismiss)
        }
        .hoverLabel("\(title) date")
        .accessibilityLabel(day.map { "\(title) \($0.relativeLabel(today: today))" } ?? "Set \(title.lowercased()) date")
    }
}

/// Quiet style: unset values are plain secondary text that gains a soft
/// background on hover; set values show their own badge.
private struct MetadataButtonStyle: ButtonStyle {
    let isSet: Bool

    func makeBody(configuration: Configuration) -> some View {
        MetadataButtonBody(configuration: configuration, isSet: isSet)
    }
}

private struct MetadataButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isSet: Bool
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.system(size: 12))
            .foregroundStyle(isSet ? SNColor.textPrimary : SNColor.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                if isHovered { Capsule().fill(SNColor.borderSubtle.opacity(0.55)) }
            }
            .contentShape(Capsule())
            .snPressEffect(configuration.isPressed)
            .snAnimation(SNMotion.hover, value: isHovered)
            .onHover { isHovered = $0 }
    }
}
