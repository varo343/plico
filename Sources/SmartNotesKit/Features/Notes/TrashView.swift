import SwiftUI

/// Deleted notes with Restore and confirmed permanent deletion. No Archive.
struct TrashView: View {
    let model: NotesModel
    @State private var pendingDelete: NoteSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.trashed.isEmpty {
                EmptyState(symbol: "trash", tint: SNColor.borderSubtle, title: "Trash is empty",
                           message: "Deleted notes wait here until you empty the Trash. Nothing is removed automatically.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.trashed) { note in
                            TrashRow(note: note, restore: { model.restore(note.id) }, delete: { pendingDelete = note })
                        }
                    }
                    .padding(.horizontal, SNSpacing.xs)
                }
            }
        }
        .confirmDestructiveAction(
            "Delete “\(pendingDelete?.displayTitle ?? "")” permanently?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            message: "This can't be undone.",
            actionTitle: "Delete Permanently"
        ) {
            if let note = pendingDelete { model.deletePermanently(note.id) }
            pendingDelete = nil
        }
    }
}

private struct TrashRow: View {
    let note: NoteSummary
    let restore: () -> Void
    let delete: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.displayTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SNColor.textPrimary)
                .lineLimit(2)
            HStack(spacing: SNSpacing.xs) {
                if let deletedAt = note.deletedAt {
                    Text("Deleted \(deletedAt.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 11))
                        .foregroundStyle(SNColor.textSecondary)
                }
                Spacer()
                Button(action: restore) {
                    HStack(spacing: 4) {
                        MotionIcon(symbol: "arrow.uturn.backward", size: 11, weight: .semibold)
                        Text("Restore")
                    }
                }
                .buttonStyle(SNCapsuleButtonStyle())
                Button(action: delete) {
                    MotionIcon(symbol: "xmark.bin", size: 12)
                }
                .buttonStyle(SNIconButtonStyle(shape: .capsule))
                .hoverLabel("Delete permanently…")
                .accessibilityLabel("Delete \(note.displayTitle) permanently")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SNSpacing.s)
        .padding(.vertical, 10)
        .background(isHovered ? SNColor.borderSubtle.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: SNRadius.standard))
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .contextMenu {
            Button("Restore", action: restore)
            Button("Delete Permanently…", role: .destructive, action: delete)
        }
    }
}

/// "Empty Trash…" in the header, with its confirmation.
struct EmptyTrashButton: View {
    let model: NotesModel
    @State private var confirm = false

    var body: some View {
        Button { confirm = true } label: {
            HStack(spacing: 4) {
                MotionIcon(symbol: "trash", size: 11, weight: .semibold)
                Text("Empty")
            }
        }
        .buttonStyle(SNCapsuleButtonStyle(isDestructive: true))
        .disabled(model.trashed.isEmpty)
        .hoverLabel("Empty Trash: delete \(model.trashed.count) note(s) permanently")
        .confirmDestructiveAction(
            "Empty Trash?",
            isPresented: $confirm,
            message: "\(model.trashed.count) note(s) will be deleted permanently. This can't be undone.",
            actionTitle: "Empty Trash"
        ) {
            model.emptyTrash()
        }
    }
}
