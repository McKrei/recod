import SwiftUI

struct SystemPromptOverrideSection: View {
    let hasCustomPrompt: Bool
    let editPrompt: () -> Void
    let resetPrompt: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: AppTheme.spacing) {
                HStack(spacing: AppTheme.spacing) {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Prompt Override")
                            .font(.subheadline.weight(.semibold))

                        Text(hasCustomPrompt ? "This action uses a custom system prompt." : "This action uses the default global system prompt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(hasCustomPrompt ? "Custom" : "Default")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(hasCustomPrompt ? .primary : .secondary)
                }

                HStack(spacing: AppTheme.spacing) {
                    Button(hasCustomPrompt ? "Edit Override" : "Add Override", action: editPrompt)
                        .buttonStyle(.bordered)

                    if hasCustomPrompt {
                        Button("Use Default", action: resetPrompt)
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .groupBoxStyle(GlassGroupBoxStyle())
    }
}
