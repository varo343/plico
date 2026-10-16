import SwiftUI

/// Standard confirmation for irreversible actions (permanent delete, Empty Trash).
struct ConfirmDestructiveAction: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let message: String
    let actionTitle: String
    let action: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
            Button(actionTitle, role: .destructive, action: action)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

extension View {
    func confirmDestructiveAction(
        _ title: String, isPresented: Binding<Bool>, message: String, actionTitle: String, action: @escaping () -> Void
    ) -> some View {
        modifier(ConfirmDestructiveAction(title: title, isPresented: isPresented, message: message, actionTitle: actionTitle, action: action))
    }
}
