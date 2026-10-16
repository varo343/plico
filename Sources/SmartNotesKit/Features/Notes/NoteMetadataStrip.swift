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
            HStack(alignment: .top, spacing: SNSpacing.xs) {
                metadata(summary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                actions(summary)
            }
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

    /// Formatting toggle and note actions, next to what they act on.
    private func actions(_ summary: NoteSummary) -> some View {
        HStack(spacing: 2) {
            if let editor = notes.editor, editor.note.id == noteID {
                Button { editor.showsFormattingBar.toggle() } label: {
                    Text("Aa").font(.system(size: 12.5, weight: .semibold))
                }
                .buttonStyle(SNIconButtonStyle(isActive: editor.showsFormattingBar, size: CGSize(width: 30, height: 26)))
                .hoverLabel(editor.showsFormattingBar ? "Hide formatting" : "Show formatting")
                .accessibilityLabel("Formatting controls")
                .accessibilityValue(editor.showsFormattingBar ? "Shown" : "Hidden")
            }
            SNDropdown(minWidth: 190, showsChevron: false) {
                [
                    .item(SNMenuItem(title: summary.isPinned ? "Unpin" : "Pin", icon: summary.isPinned ? "pin.slash" : "pin", shortcut: "⇧⌘P") { notes.togglePin(noteID) }),
                    .item(SNMenuItem(title: "Duplicate", icon: "plus.square.on.square", shortcut: "⌘D") { notes.duplicate(noteID) }),
                    .divider(),
                    .item(SNMenuItem(title: "Move to Trash", icon: "trash", isDestructive: true, shortcut: "⌘⌫") { notes.moveToTrash(noteID) }),
                ]
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold))
            }
            .hoverLabel("Note actions")
            .accessibilityLabel("Note actions")
        }
        .foregroundStyle(SNColor.textPrimary)
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
            VStack(alignment: .leading, spacing: SNSpacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(title) date").font(.system(size: 13, weight: .semibold))
                    Text(explanation).font(SNFont.secondary).foregroundStyle(SNColor.textSecondary)
                }
                DatePicker(
                    title,
                    selection: Binding(get: { (day ?? today).startDate() }, set: { change(LocalDay(date: $0)) }),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                HStack(spacing: SNSpacing.xxs) {
                    Button("Today") { change(today); dismiss() }
                    Button("Tomorrow") { change(today.adding(days: 1)); dismiss() }
                    Button("Next week") { change(today.adding(days: 7)); dismiss() }
                    Spacer(minLength: SNSpacing.xs)
                    Button("Clear") { change(nil); dismiss() }
                        .disabled(day == nil)
                }
                .buttonStyle(SNCapsuleButtonStyle())
            }
            .padding(SNSpacing.s)
            .frame(width: 300)
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
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Capsule())
            .onHover { isHovered = $0 }
    }
}
