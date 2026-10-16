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

/// Quiet style for unset metadata; set values show their own chip.
private struct MetadataButtonStyle: ButtonStyle {
    let isSet: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.system(size: 12))
            .foregroundStyle(isSet ? SNColor.textPrimary : SNColor.textSecondary)
            .padding(.horizontal, isSet ? 0 : 6)
            .padding(.vertical, isSet ? 0 : 3)
            .background {
                if !isSet {
                    Capsule().stroke(SNColor.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Capsule())
    }
}
