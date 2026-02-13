import SwiftUI
import SwiftData

struct ModelsSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        let modelManager = appState.whisperModelManager
        
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                GroupBox {
                    HStack(spacing: 16) {
                        Image(systemName: "cpu")
                            .font(.system(size: 32))
                            .foregroundStyle(.primary)
                            .frame(width: 40)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Speech Recognition Models")
                                .font(.headline)
                            
                            Text("Select a model to use for transcription. Larger models are more accurate but slower and require more disk space.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(8)
                }
                .groupBoxStyle(GlassGroupBoxStyle())
                
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
