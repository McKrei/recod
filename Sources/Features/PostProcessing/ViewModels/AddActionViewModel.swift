import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AddActionViewModel {
    static let fileTemplatePlaceholders = ["{YYYY}", "{YY}", "{MM}", "{DD}", "{HH}", "{mm}", "{ss}"]

    let actionToEdit: PostProcessingAction?

    var actionName = "New Action"
    var promptText = PostProcessingPromptBuilder.defaultPrompt
    var systemPromptText = ""
    var modelID = ""
    var selectedProviderID = ""
    var providerAPIKey = ""
    var customProviderName = ""
    var customBaseURL = LLMProvider.customDefaultBaseURL
    var providers: [LLMProvider] = []
    var availableModels: [String] = []
    var isLoadingModels = false
    var modelsError: String?
    var saveToFileEnabled = false
    var saveToFileMode: SaveToFileMode = .newFile
    var saveToFileDirectoryPath = ""
    var saveToFileExistingFilePath = ""
    var saveToFileTemplate = PostProcessingAction.defaultSaveToFileTemplate
    var saveToFileSeparator = PostProcessingAction.defaultSaveToFileSeparator
    var saveToFileExtension = PostProcessingAction.defaultSaveToFileExtension

    private var modelsFetchTask: Task<Void, Never>?
    private var hasPrepared = false
    private var isHydratingState = false

    init(actionToEdit: PostProcessingAction?) {
        self.actionToEdit = actionToEdit
    }

    var isEditing: Bool {
        actionToEdit != nil
    }

    var selectedProvider: LLMProvider? {
        providers.first(where: { $0.id == selectedProviderID })
    }

    var canSave: Bool {
        !actionName.isBlank
            && !modelID.isBlank
            && selectedProvider != nil
    }

    var hasCustomSystemPrompt: Bool {
        !systemPromptText.isBlank
    }

    func prepare() {
        guard !hasPrepared else { return }
        hasPrepared = true

        loadProviders()
        hydrateForEditingIfNeeded()
        ensureInitialProviderSelection()
    }

    func tearDown() {
        modelsFetchTask?.cancel()
        modelsFetchTask = nil
    }

    func handleSelectedProviderChange() {
        guard !isHydratingState else { return }
        providerDidChange()
    }

    func handleCustomBaseURLChange() {
        guard !isHydratingState, selectedProvider?.isCustom == true else { return }
        refreshModelsDebounced()
    }

    func handleProviderAPIKeyChange() {
        guard !isHydratingState else { return }
        refreshModelsDebounced()
    }

    func refreshModels() {
        guard let provider = selectedProvider else { return }

        modelsFetchTask?.cancel()
        isLoadingModels = true
        modelsError = nil

        let baseURL = resolvedBaseURL(for: provider)
        let apiKey = providerAPIKey.trimmed()

        Task {
            await FileLogger.shared.log(
                "UI refresh models: provider=\(provider.displayName), baseURL=\(baseURL), keyProvided=\(!apiKey.isEmpty)",
                level: .debug
            )
        }

        modelsFetchTask = Task { [weak self] in
            do {
                let fetched = try await LLMService.shared.fetchModels(
                    baseURL: baseURL,
                    apiKey: apiKey.isEmpty ? nil : apiKey
                )

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.availableModels = fetched
                    if !fetched.contains(self.modelID) {
                        self.modelID = fetched.first ?? ""
                    }
                    self.isLoadingModels = false
                }
                await FileLogger.shared.log("UI models loaded: count=\(fetched.count)", level: .debug)
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.availableModels = []
                    self.modelID = ""
                    self.modelsError = error.localizedDescription
                    self.isLoadingModels = false
                }
                await FileLogger.shared.log("UI models load failed: \(error.localizedDescription)", level: .error)
            }
        }
    }

    func insertPromptPlaceholder(_ placeholder: String) {
        promptText = PostProcessingPromptBuilder.insertPlaceholder(placeholder, into: promptText)
    }

    func chooseDirectory() {
        if let path = FilePanelService.chooseDirectory() {
            saveToFileDirectoryPath = path
        }
    }

    func chooseExistingFile() {
        if let path = FilePanelService.chooseTextFile() {
            saveToFileExistingFilePath = path
        }
    }

    func saveAction(in modelContext: ModelContext) -> Bool {
        guard let provider = selectedProvider else { return false }

        let cleanName = actionName.trimmed()
        let cleanPrompt = promptText.trimmed()
        let cleanSystemPrompt = systemPromptText.trimmed()
        let cleanModel = modelID.trimmed()
        guard !cleanName.isEmpty, !cleanModel.isEmpty else { return false }

        let providerID = resolvedProviderID(from: provider)
        persistAPIKey(for: providerID)

        Task {
            await FileLogger.shared.log(
                "Action save: name=\(cleanName), providerID=\(providerID), model=\(cleanModel), auto=false",
                level: .info
            )
        }

        let resolvedSavePath = Self.resolvedSavePath(
            mode: saveToFileMode,
            directoryPath: saveToFileDirectoryPath,
            existingFilePath: saveToFileExistingFilePath
        )

        if let action = actionToEdit {
            action.name = cleanName
            action.prompt = cleanPrompt
            action.systemPrompt = cleanSystemPrompt.isEmpty ? nil : cleanSystemPrompt
            action.providerID = providerID
            action.modelID = cleanModel
            action.saveToFileEnabled = saveToFileEnabled
            action.saveToFileMode = saveToFileMode.rawValue
            action.saveToFilePath = resolvedSavePath
            action.saveToFileTemplate = saveToFileTemplate
            action.saveToFileSeparator = saveToFileSeparator
            action.saveToFileExtension = saveToFileExtension
        } else {
            let action = PostProcessingAction(
                name: cleanName,
                prompt: cleanPrompt,
                systemPrompt: cleanSystemPrompt.isEmpty ? nil : cleanSystemPrompt,
                providerID: providerID,
                modelID: cleanModel,
                saveToFileEnabled: saveToFileEnabled,
                saveToFileMode: saveToFileMode.rawValue,
                saveToFilePath: resolvedSavePath,
                saveToFileTemplate: saveToFileTemplate,
                saveToFileSeparator: saveToFileSeparator,
                saveToFileExtension: saveToFileExtension
            )
            modelContext.insert(action)
        }

        return true
    }

    nonisolated static func resolvedSavePath(
        mode: SaveToFileMode,
        directoryPath: String,
        existingFilePath: String
    ) -> String? {
        let rawPath = mode == .newFile ? directoryPath : existingFilePath
        let trimmed = rawPath.trimmed()
        return trimmed.isEmpty ? nil : trimmed
    }

    private func loadProviders() {
        providers = LLMProviderStore.allProviders() + [
            LLMProvider(
                id: BuiltinProviderID.custom.rawValue,
                displayName: "Custom",
                baseURL: LLMProvider.customDefaultBaseURL,
                isCustom: true,
                defaultModels: []
            )
        ]
    }

    private func hydrateForEditingIfNeeded() {
        guard let action = actionToEdit else { return }

        isHydratingState = true
        defer { isHydratingState = false }

        actionName = action.name
        promptText = PostProcessingPromptBuilder.resolvedPrompt(action.prompt)
        systemPromptText = action.trimmedSystemPrompt ?? ""
        modelID = action.modelID
        selectedProviderID = action.providerID
        providerAPIKey = KeychainService.loadAPIKey(forProviderID: action.providerID) ?? ""

        if let provider = LLMProviderStore.provider(for: action.providerID), provider.isCustom {
            customProviderName = provider.displayName
            customBaseURL = provider.baseURL
        }

        saveToFileEnabled = action.saveToFileEnabled
        saveToFileMode = action.fileSaveMode
        let storedPath = action.saveToFilePath ?? ""
        saveToFileDirectoryPath = action.fileSaveMode == .newFile ? storedPath : ""
        saveToFileExistingFilePath = action.fileSaveMode == .existingFile ? storedPath : ""
        saveToFileTemplate = action.saveToFileTemplate ?? PostProcessingAction.defaultSaveToFileTemplate
        saveToFileSeparator = action.saveToFileSeparator ?? PostProcessingAction.defaultSaveToFileSeparator
        saveToFileExtension = action.saveToFileExtension ?? PostProcessingAction.defaultSaveToFileExtension
    }

    private func ensureInitialProviderSelection() {
        if selectedProviderID.isEmpty {
            selectedProviderID = BuiltinProviderID.openAI.rawValue
        }
        providerDidChange()
    }

    private func providerDidChange() {
        guard let provider = selectedProvider else { return }

        modelsError = nil
        availableModels = []

        if provider.isCustom {
            if customBaseURL.isBlank {
                customBaseURL = LLMProvider.customDefaultBaseURL
            }
            if customProviderName.isBlank,
               provider.id != BuiltinProviderID.custom.rawValue {
                customProviderName = provider.displayName
            }
        }

        isHydratingState = true
        providerAPIKey = KeychainService.loadAPIKey(forProviderID: provider.id) ?? ""
        isHydratingState = false
        refreshModels()
    }

    private func refreshModelsDebounced() {
        modelsFetchTask?.cancel()
        modelsFetchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.refreshModels()
            }
        }
    }

    private func resolvedBaseURL(for provider: LLMProvider) -> String {
        if provider.isCustom {
            return customBaseURL.trimmed()
        }
        return provider.baseURL
    }

    private func resolvedProviderID(from provider: LLMProvider) -> String {
        guard provider.isCustom else { return provider.id }

        let customProviderID = provider.id == BuiltinProviderID.custom.rawValue
            ? nil
            : provider.id
        let customProvider = LLMProviderStore.upsertCustomProvider(
            id: customProviderID,
            displayName: customProviderName,
            baseURL: customBaseURL
        )
        return customProvider.id
    }

    private func persistAPIKey(for providerID: String) {
        let cleanKey = providerAPIKey.trimmed()
        if cleanKey.isEmpty {
            try? KeychainService.deleteAPIKey(forProviderID: providerID)
        } else {
            try? KeychainService.saveAPIKey(cleanKey, forProviderID: providerID)
        }
    }
}
