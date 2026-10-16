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
                        .frame(width: 30, height: 24)
                        .background(editor.showsFormattingBar ? SNColor.borderSubtle : .clear, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .foregroundStyle(SNColor.textPrimary)
                .help(editor.showsFormattingBar ? "Hide formatting" : "Show formatting")
                .accessibilityLabel("Formatting controls")
                .accessibilityValue(editor.showsFormattingBar ? "Shown" : "Hidden")
            }
            Menu {
                Button(summary.isPinned ? "Unpin" : "Pin") { notes.togglePin(noteID) }
                Button("Duplicate") { notes.duplicate(noteID) }
                Divider()
                Button("Move to Trash", role: .destructive) { notes.moveToTrash(noteID) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 30, height: 24)
            .help("Note actions")
            .accessibilityLabel("Note actions")
        }
    }
}

/// Priority as a real badge (menus would strip its styling) with a popover of choices.
private struct PriorityField: View {
    let priority: Priority
    let change: (Priority) -> Void
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            if priority == .none {
                Label("Priority", systemImage: "flag")
            } else {
                PriorityBadge(priority)
            }
        }
        .buttonStyle(MetadataButtonStyle(isSet: priority != .none))
        .help("Priority (never set automatically)")
        .accessibilityLabel("Priority, \(priority.label)")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            Picker("Priority", selection: Binding(get: { priority }, set: { change($0); isPresented = false })) {
                ForEach(Priority.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .padding(SNSpacing.m)
        }
    }
}

/// Planned or due date with a calendar popover and quick choices.
private struct DateField: View {
    let kind: DateMetadataChip.Kind
    let day: LocalDay?
    let today: LocalDay
    let change: (LocalDay?) -> Void
    @State private var isPresented = false

    private var title: String { kind == .planned ? "Planned" : "Due" }
    private var explanation: String {
        kind == .planned ? "When you intend to work on this note." : "The deadline for this note."
    }

    var body: some View {
        Button { isPresented = true } label: {
            if let day {
                DateMetadataChip(kind, day: day, today: today)
            } else {
                Label(title, systemImage: kind == .planned ? "calendar" : "flag.checkered")
            }
        }
        .buttonStyle(MetadataButtonStyle(isSet: day != nil))
        .help("\(title) date: \(explanation)")
        .accessibilityLabel(day.map { "\(title) \($0.relativeLabel(today: today))" } ?? "Set \(title.lowercased()) date")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: SNSpacing.s) {
                Text("\(title) date").font(SNFont.rowTitle)
                Text(explanation).font(SNFont.secondary).foregroundStyle(SNColor.textSecondary)
                DatePicker(
                    title,
                    selection: Binding(
                        get: { (day ?? today).startDate() },
                        set: { change(LocalDay(date: $0)) }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                HStack {
                    Button("Today") { change(today); isPresented = false }
                    Button("Tomorrow") { change(today.adding(days: 1)); isPresented = false }
                    Button("Next Week") { change(today.adding(days: 7)); isPresented = false }
                    Spacer()
                    Button("Clear", role: .destructive) { change(nil); isPresented = false }
                        .disabled(day == nil)
                }
            }
            .padding(SNSpacing.m)
            .frame(width: 300)
        }
    }
}

/// Quiet style: unset values are plain secondary text that gains a soft
/// background on hover; set values show their own chip.
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
            .padding(.horizontal, isSet ? 0 : 7)
            .padding(.vertical, isSet ? 0 : 3)
            .background {
                if !isSet, isHovered { Capsule().fill(SNColor.borderSubtle.opacity(0.5)) }
            }
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Capsule())
            .onHover { isHovered = $0 }
    }
}
