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
                                .glidingHoverRow(note.id)
                        }
                    }
                    .glidingHover(color: SNColor.borderSubtle.opacity(0.35))
                    .padding(.horizontal, SNSpacing.xs)
                }
                EmptyTrashButton(model: model)
                    .frame(maxWidth: .infinity)
                    .padding(SNSpacing.s)
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
                        .lineLimit(1)
                }
                Spacer()
                actions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SNSpacing.s)
        .padding(.vertical, 10)
        .contentShape(RoundedRectangle(cornerRadius: SNRadius.standard))
        // The hover highlight is the list's (`glidingHover`); hovering still shows the actions.
        .onHover { isHovered = $0 }
        .snAnimation(SNMotion.hover, value: isHovered)
        .accessibilityElement(children: .contain)
        .contextMenu {
            Button("Restore", action: restore)
            Button("Delete Permanently…", role: .destructive, action: delete)
        }
    }

    /// Shown on hover only; the space stays reserved so the date doesn't reflow.
    private var actions: some View {
        HStack(spacing: 2) {
            Button(action: restore) {
                MotionIcon(symbol: "arrow.uturn.backward", size: 12)
            }
            .buttonStyle(SNIconButtonStyle(shape: .capsule))
            .hoverLabel("Restore")
            .accessibilityLabel("Restore \(note.displayTitle)")
            Button(action: delete) {
                MotionIcon(symbol: "trash", size: 12)
            }
            .buttonStyle(SNIconButtonStyle(shape: .capsule))
            .hoverLabel("Delete permanently…")
            .accessibilityLabel("Delete \(note.displayTitle) permanently")
        }
        .opacity(isHovered ? 1 : 0)
        .allowsHitTesting(isHovered)
    }
}

/// "Empty Trash…" below the list, with its confirmation.
struct EmptyTrashButton: View {
    let model: NotesModel
    @State private var confirm = false

    var body: some View {
        Button { confirm = true } label: {
            HStack(spacing: 4) {
                MotionIcon(symbol: "trash", size: 11, weight: .semibold)
                Text("Empty Trash")
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
