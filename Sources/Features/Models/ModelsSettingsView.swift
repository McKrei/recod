import SwiftUI
import SwiftData

struct ModelsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: TranscriptionEngine = .whisperKit

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                SettingsHeaderView(
                    title: "Speech Recognition Models",
                    subtitle: "Choose transcription engine and model. Larger models are more accurate but slower.",
                    systemImage: "cpu"
                )

                // MARK: - Engine Selector

                Picker("Engine", selection: $selectedTab) {
                    ForEach(TranscriptionEngine.allCases) { engine in
                        Label(engine.displayName, systemImage: engine.iconName)
                            .tag(engine)
                    }
                }
                .pickerStyle(.segmented)
                .onAppear {
                    // Set the tab to the currently active engine ONLY ONCE when view appears.
                    // Notice we removed .onChange: switching tabs DOES NOT switch the engine.
                    selectedTab = appState.selectedEngine
                }

                Text(selectedTab.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // MARK: - Tab Content

                switch selectedTab {
                case .whisperKit:
                    whisperKitModelsList

                case .parakeet:
                    parakeetModelsList
                }
            }
            .padding(AppTheme.pagePadding)
        }
    }

    // MARK: - WhisperKit Models List

    private var whisperKitModelsList: some View {
        let modelManager = appState.whisperModelManager

        return VStack(spacing: AppTheme.spacing) {
            ForEach(modelManager.models) { model in
                WhisperModelRow(
                    model: model,
                    isSelected: (appState.selectedEngine == .whisperKit) && (modelManager.selectedModelId == model.id),
                    onSelect: {
                        withAnimation {
                            modelManager.selectModel(model)
                            appState.selectedEngine = .whisperKit
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

    // MARK: - Parakeet Models List

    private var parakeetModelsList: some View {
        let modelManager = appState.parakeetModelManager

        return VStack(spacing: AppTheme.spacing) {
            ForEach(modelManager.models) { model in
                ParakeetModelRow(
                    model: model,
                    isSelected: (appState.selectedEngine == .parakeet) && (modelManager.selectedModelId == model.id),
                    onSelect: {
                        withAnimation {
                            modelManager.selectModel(model)
                            appState.selectedEngine = .parakeet
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
}

#Preview {
    ModelsSettingsView()
}
