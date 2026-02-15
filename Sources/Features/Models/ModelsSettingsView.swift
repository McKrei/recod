import SwiftUI
import SwiftData

struct ModelsSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        let modelManager = appState.whisperModelManager

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                SettingsHeaderView(
                    title: "Speech Recognition Models",
                    subtitle: "Select a model to use for transcription. Larger models are more accurate but slower and require more disk space.",
                    systemImage: "cpu"
                )

                VStack(spacing: AppTheme.spacing) {
                    ForEach(modelManager.models) { model in
                        WhisperModelRow(
                            model: model,
                            isSelected: modelManager.selectedModelId == model.id,
                            onSelect: {
                                withAnimation {
                                    modelManager.selectModel(model)
                                }
                            },
                            onDownload: {
                                withAnimation {
                                    modelManager.downloadModel(model)
                                }
                            },
                            onCancel: {
                                withAnimation {
                                    modelManager.cancelDownload(model)
                                }
                            },
                            onDelete: {
                                withAnimation {
                                    modelManager.deleteModel(model)
                                }
                            }
                        )
                    }
                }
            }
            .padding(AppTheme.pagePadding)
        }
    }
}

#Preview {
    ModelsSettingsView()
}
