import SwiftUI

struct ActionModalFooter: View {
    let isEditing: Bool
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack {
            Spacer()

            Button("Cancel", role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button(isEditing ? "Save" : "Add", action: onSave)
                .buttonStyle(.bordered)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, AppTheme.padding)
        .padding(.top, AppTheme.spacing)
        .padding(.bottom, AppTheme.padding)
    }
}
