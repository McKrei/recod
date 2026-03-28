import SwiftUI

struct PromptEditorSection: View {
    @Binding var promptText: String

    let insertPlaceholder: (String) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt")
                    .font(.subheadline.weight(.semibold))

                TextEditor(text: $promptText)
                    .font(.body)
                    .frame(minHeight: 160)
                    .padding(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.smallCornerRadius)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: AppTheme.spacing) {
                    Text("Quick placeholders")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: AppTheme.spacing) {
                        ForEach(PostProcessingPromptBuilder.supportedPlaceholders, id: \.self) { placeholder in
                            Button(placeholder) {
                                insertPlaceholder(placeholder)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .groupBoxStyle(GlassGroupBoxStyle())
    }
}
