import Observation
import SwiftData
import SwiftUI

struct AddActionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: AddActionViewModel
    @State private var showingSystemPromptSheet = false

    init(actionToEdit: PostProcessingAction?) {
        _viewModel = State(initialValue: AddActionViewModel(actionToEdit: actionToEdit))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                formContent
            }

            ActionModalFooter(
                isEditing: viewModel.isEditing,
                canSave: viewModel.canSave,
                onCancel: { dismiss() },
                onSave: {
                    if viewModel.saveAction(in: modelContext) {
                        dismiss()
                    }
                }
            )
        }
        .frame(minWidth: 620, maxWidth: 620, minHeight: 560, maxHeight: 760)
        .background(.ultraThinMaterial)
        .task {
            viewModel.prepare()
        }
        .onDisappear {
            viewModel.tearDown()
        }
        .onChange(of: viewModel.selectedProviderID) { _, _ in
            viewModel.handleSelectedProviderChange()
        }
        .onChange(of: viewModel.customBaseURL) { _, _ in
            viewModel.handleCustomBaseURLChange()
        }
        .onChange(of: viewModel.providerAPIKey) { _, _ in
            viewModel.handleProviderAPIKeyChange()
        }
        .sheet(isPresented: $showingSystemPromptSheet) {
            SystemPromptEditorSheet(
                title: viewModel.isEditing ? "Edit System Prompt Override" : "Add System Prompt Override",
                subtitle: "Use a custom system prompt for this action. Reset it to fall back to the global default.",
                placeholder: PostProcessingPromptDefaults.systemPrompt,
                resetButtonTitle: "Use Default",
                initialText: viewModel.systemPromptText,
                onReset: {
                    viewModel.systemPromptText = ""
                },
                onSave: { value in
                    viewModel.systemPromptText = value
                }
            )
        }
    }

    private var formContent: some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.isEditing ? "Edit Action" : "Add Action")
                .font(.headline)

            ProviderConfigurationSection(
                actionName: $viewModel.actionName,
                selectedProviderID: $viewModel.selectedProviderID,
                providerAPIKey: $viewModel.providerAPIKey,
                customProviderName: $viewModel.customProviderName,
                customBaseURL: $viewModel.customBaseURL,
                modelID: $viewModel.modelID,
                providers: viewModel.providers,
                selectedProviderIsCustom: viewModel.selectedProvider?.isCustom == true,
                availableModels: viewModel.availableModels,
                isLoadingModels: viewModel.isLoadingModels,
                modelsError: viewModel.modelsError,
                refreshModels: viewModel.refreshModels
            )
            SystemPromptOverrideSection(
                hasCustomPrompt: viewModel.hasCustomSystemPrompt,
                editPrompt: { showingSystemPromptSheet = true },
                resetPrompt: { viewModel.systemPromptText = "" }
            )
            PromptEditorSection(
                promptText: $viewModel.promptText,
                insertPlaceholder: viewModel.insertPromptPlaceholder
            )
            AddActionSaveToFileSection(
                saveToFileEnabled: $viewModel.saveToFileEnabled,
                saveToFileMode: $viewModel.saveToFileMode,
                saveToFileDirectoryPath: $viewModel.saveToFileDirectoryPath,
                saveToFileExistingFilePath: $viewModel.saveToFileExistingFilePath,
                saveToFileTemplate: $viewModel.saveToFileTemplate,
                saveToFileSeparator: $viewModel.saveToFileSeparator,
                saveToFileExtension: $viewModel.saveToFileExtension,
                defaultFileTemplate: PostProcessingAction.defaultSaveToFileTemplate,
                defaultSeparator: PostProcessingAction.defaultSaveToFileSeparator,
                fileTemplatePlaceholders: AddActionViewModel.fileTemplatePlaceholders,
                chooseDirectory: viewModel.chooseDirectory,
                chooseExistingFile: viewModel.chooseExistingFile,
                abbreviatePath: FilePanelService.abbreviatePath
            )
        }
        .padding(AppTheme.padding)
    }
}

#Preview {
    AddActionView(actionToEdit: nil)
        .modelContainer(for: PostProcessingAction.self, inMemory: true)
}
