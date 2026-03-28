import SwiftUI

struct SystemPromptEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String
    let placeholder: String
    let resetButtonTitle: String
    let saveButtonTitle: String
    let initialText: String
    let onReset: () -> Void
    let onSave: (String) -> Void

    @State private var draftText: String

    init(
        title: String,
        subtitle: String,
        placeholder: String,
        resetButtonTitle: String,
        saveButtonTitle: String = "Save",
        initialText: String,
        onReset: @escaping () -> Void,
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.placeholder = placeholder
        self.resetButtonTitle = resetButtonTitle
        self.saveButtonTitle = saveButtonTitle
        self.initialText = initialText
        self.onReset = onReset
        self.onSave = onSave
        _draftText = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.padding) {
                    SettingsHeaderView(
                        title: title,
                        subtitle: subtitle,
                        systemImage: "text.bubble"
                    )

                    GroupBox {
                        VStack(alignment: .leading, spacing: AppTheme.spacing) {
                            Text("System Prompt")
                                .font(.subheadline.weight(.semibold))

                            ZStack(alignment: .topLeading) {
                                if draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(placeholder)
                                        .font(.body)
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 14)
                                }

                                TextEditor(text: $draftText)
                                    .font(.body)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 220)
                                    .padding(6)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.smallCornerRadius)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                        }
                    }
                    .groupBoxStyle(GlassGroupBoxStyle())
                }
                .padding(AppTheme.padding)
            }

            HStack {
                Button(resetButtonTitle) {
                    onReset()
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(saveButtonTitle) {
                    onSave(draftText.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, AppTheme.padding)
            .padding(.top, AppTheme.spacing)
            .padding(.bottom, AppTheme.padding)
        }
        .frame(minWidth: 640, maxWidth: 640, minHeight: 420, maxHeight: 560)
        .background(.ultraThinMaterial)
    }
}
