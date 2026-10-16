import SwiftUI

/// Deleted notes with Restore and confirmed permanent deletion. No Archive.
struct TrashView: View {
    let model: NotesModel
    @State private var pendingDelete: NoteSummary?
    @State private var confirmEmpty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Trash").font(SNFont.section).foregroundStyle(SNColor.textPrimary)
                Spacer()
                Button("Empty Trash") { confirmEmpty = true }
                    .disabled(model.trashed.isEmpty)
            }
            .padding(.horizontal, SNSpacing.m)
            .padding(.vertical, SNSpacing.s)

            if model.trashed.isEmpty {
                EmptyState(symbol: "trash", title: "Trash is empty",
                           message: "Deleted notes stay here until you empty the Trash.")
            } else {
                List(model.trashed) { note in
                    TrashRow(note: note, restore: { model.restore(note.id) }, delete: { pendingDelete = note })
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(SNColor.card)
        .confirmDestructiveAction(
            "Delete “\(pendingDelete?.displayTitle ?? "")” permanently?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            message: "This can't be undone.",
            actionTitle: "Delete Permanently"
        ) {
            if let note = pendingDelete { model.deletePermanently(note.id) }
            pendingDelete = nil
        }
        .confirmDestructiveAction(
            "Empty Trash?",
            isPresented: $confirmEmpty,
            message: "\(model.trashed.count) note(s) will be deleted permanently. This can't be undone.",
            actionTitle: "Empty Trash"
        ) {
            model.emptyTrash()
        }
    }
}

private struct TrashRow: View {
    let note: NoteSummary
    let restore: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: SNSpacing.s) {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.displayTitle).font(SNFont.rowTitle).foregroundStyle(SNColor.textPrimary).lineLimit(1)
                if let deletedAt = note.deletedAt {
                    Text("Deleted \(deletedAt.formatted(.relative(presentation: .named)))")
                        .font(SNFont.secondary)
                        .foregroundStyle(SNColor.textSecondary)
                }
            }
            Spacer()
            Button("Restore", action: restore)
            Button(role: .destructive, action: delete) {
                Image(systemName: "trash.slash")
            }
            .help("Delete permanently")
            .accessibilityLabel("Delete \(note.displayTitle) permanently")
        }
        .padding(.vertical, SNSpacing.xxs)
        .contextMenu {
            Button("Restore", action: restore)
            Button("Delete Permanently…", role: .destructive, action: delete)
        }
    }
}
