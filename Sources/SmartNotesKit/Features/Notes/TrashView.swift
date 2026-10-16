import SwiftUI

/// Deleted notes with Restore and confirmed permanent deletion. No Archive.
struct TrashView: View {
    let model: NotesModel
    @State private var pendingDelete: NoteSummary?
    @State private var confirmEmpty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Trash").font(.system(size: 22, weight: .bold)).foregroundStyle(SNColor.textPrimary)
                Text("\(model.trashed.count)")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(SNColor.textSecondary)
                Spacer()
                Button("Empty Trash…") { confirmEmpty = true }
                    .buttonStyle(SNCapsuleButtonStyle(isDestructive: true))
                    .disabled(model.trashed.isEmpty)
            }
            .padding(.horizontal, SNSpacing.m)
            .padding(.top, SNSpacing.xs)
            .padding(.bottom, SNSpacing.s)

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
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(SNCapsuleButtonStyle())
                Button(action: delete) {
                    Image(systemName: "xmark.bin").font(.system(size: 12))
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
