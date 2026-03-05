import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct AddActionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let actionToEdit: PostProcessingAction?

    @State private var actionName = "New Action"
    @State private var promptText = Self.defaultPrompt
    @State private var modelID = ""
    @State private var selectedProviderID = ""

    @State private var providerAPIKey = ""
    @State private var customProviderName = ""
    @State private var customBaseURL = LLMProvider.customDefaultBaseURL

    @State private var providers: [LLMProvider] = []
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var modelsError: String?
    @State private var modelsFetchTask: Task<Void, Never>?

    // Save to File
    @State private var saveToFileEnabled = false
    @State private var saveToFileMode: SaveToFileMode = .newFile
    @State private var saveToFileDirectoryPath = ""
    @State private var saveToFileExistingFilePath = ""
    @State private var saveToFileTemplate = PostProcessingAction.defaultSaveToFileTemplate
    @State private var saveToFileSeparator = PostProcessingAction.defaultSaveToFileSeparator
    @State private var saveToFileExtension = PostProcessingAction.defaultSaveToFileExtension

    private static let defaultPrompt = """
    Transcript:
    ${output}
    """

    private static let outputPlaceholder = "${output}"
    private static let outputWithTimestampsPlaceholder = "${output_with_timestamps}"
    private static let defaultFileTemplate = PostProcessingAction.defaultSaveToFileTemplate
    private static let defaultSeparator = PostProcessingAction.defaultSaveToFileSeparator
    private static let defaultExtension = PostProcessingAction.defaultSaveToFileExtension
    private static let fileTemplatePlaceholders = ["{YYYY}", "{YY}", "{MM}", "{DD}", "{HH}", "{mm}", "{ss}"]

    private var isEditing: Bool { actionToEdit != nil }

    private var selectedProvider: LLMProvider? {
        providers.first(where: { $0.id == selectedProviderID })
    }

    private var canSave: Bool {
        !actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedProvider != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                formContent
            }

            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isEditing ? "Save" : "Add") {
                    saveAction()
                }
                .buttonStyle(.bordered)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, AppTheme.padding)
            .padding(.top, AppTheme.spacing)
            .padding(.bottom, AppTheme.padding)
        }
        .frame(minWidth: 620, maxWidth: 620, minHeight: 560, maxHeight: 760)
        .background(.ultraThinMaterial)
        .onAppear {
            loadProviders()
            hydrateForEditingIfNeeded()
            ensureInitialProviderSelection()
            refreshModels()
        }
        .onDisappear {
            modelsFetchTask?.cancel()
            modelsFetchTask = nil
        }
        .onChange(of: selectedProviderID) { _, _ in
            providerDidChange()
        }
        .onChange(of: customBaseURL) { _, _ in
            guard selectedProvider?.isCustom == true else { return }
            refreshModelsDebounced()
        }
        .onChange(of: providerAPIKey) { _, _ in
            refreshModelsDebounced()
        }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "Edit Action" : "Add Action")
                .font(.headline)

            providerSection
            promptSection
            AddActionSaveToFileSection(
                saveToFileEnabled: $saveToFileEnabled,
                saveToFileMode: $saveToFileMode,
                saveToFileDirectoryPath: $saveToFileDirectoryPath,
                saveToFileExistingFilePath: $saveToFileExistingFilePath,
                saveToFileTemplate: $saveToFileTemplate,
                saveToFileSeparator: $saveToFileSeparator,
                saveToFileExtension: $saveToFileExtension,
                defaultFileTemplate: Self.defaultFileTemplate,
                defaultSeparator: Self.defaultSeparator,
                fileTemplatePlaceholders: Self.fileTemplatePlaceholders,
                chooseDirectory: chooseDirectory,
                chooseExistingFile: chooseExistingFile,
                abbreviatePath: abbreviatePath
            )
        }
        .padding(AppTheme.padding)
    }

    private var providerSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Action name", text: $actionName)

                ProviderPickerView(providers: providers, selectedProviderID: $selectedProviderID)

                if selectedProvider?.isCustom == true {
                    TextField("Custom provider name", text: $customProviderName)
                        .textFieldStyle(.roundedBorder)

                    TextField("Base URL", text: $customBaseURL)
                        .textFieldStyle(.roundedBorder)

                    Text("Default local endpoint: \(LLMProvider.customDefaultBaseURL)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SecureField("API key", text: $providerAPIKey)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Picker("Model", selection: $modelID) {
                        if availableModels.isEmpty {
                            Text(isLoadingModels ? "Loading..." : "No models")
                                .tag("")
                        }

                        ForEach(availableModels, id: \.self) { model in
                            Text(model)
                                .tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(isLoadingModels || availableModels.isEmpty)

                    if isLoadingModels {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        refreshModels()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh models")
                }

                if let modelsError, !modelsError.isEmpty {
                    Text(modelsError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .groupBoxStyle(GlassGroupBoxStyle())
    }

    private var promptSection: some View {
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
                        Button(Self.outputPlaceholder) {
                            insertPromptPlaceholder(Self.outputPlaceholder)
                        }
                        .buttonStyle(.bordered)

                        Button(Self.outputWithTimestampsPlaceholder) {
                            insertPromptPlaceholder(Self.outputWithTimestampsPlaceholder)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .groupBoxStyle(GlassGroupBoxStyle())
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

        actionName = action.name
        promptText = action.prompt.isEmpty ? Self.defaultPrompt : action.prompt
        modelID = action.modelID
        selectedProviderID = action.providerID
        providerAPIKey = KeychainService.loadAPIKey(forProviderID: action.providerID) ?? ""

        if let provider = LLMProviderStore.provider(for: action.providerID), provider.isCustom {
            customProviderName = provider.displayName
            customBaseURL = provider.baseURL
        }

        saveToFileEnabled = action.saveToFileEnabled
        saveToFileMode = action.fileSaveMode
        saveToFileDirectoryPath = ""
        saveToFileExistingFilePath = ""
        let storedPath = action.saveToFilePath ?? ""
        if action.fileSaveMode == .newFile {
            saveToFileDirectoryPath = storedPath
        } else {
            saveToFileExistingFilePath = storedPath
        }
        saveToFileTemplate = action.saveToFileTemplate ?? Self.defaultFileTemplate
        saveToFileSeparator = action.saveToFileSeparator ?? Self.defaultSeparator
        saveToFileExtension = action.saveToFileExtension ?? Self.defaultExtension
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
            if customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                customBaseURL = LLMProvider.customDefaultBaseURL
            }
            if customProviderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               provider.id != BuiltinProviderID.custom.rawValue {
                customProviderName = provider.displayName
            }
        }

        providerAPIKey = KeychainService.loadAPIKey(forProviderID: provider.id) ?? ""
        refreshModels()
    }

    private func refreshModelsDebounced() {
        modelsFetchTask?.cancel()
        modelsFetchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                refreshModels()
            }
        }
    }

    private func refreshModels() {
        guard let provider = selectedProvider else { return }

        modelsFetchTask?.cancel()
        isLoadingModels = true
        modelsError = nil

        let baseURL: String = {
            if provider.isCustom {
                return customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return provider.baseURL
        }()

        let apiKey = providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            await FileLogger.shared.log(
                "UI refresh models: provider=\(provider.displayName), baseURL=\(baseURL), keyProvided=\(!apiKey.isEmpty)",
                level: .debug
            )
        }

        modelsFetchTask = Task {
            do {
                let fetched = try await LLMService.shared.fetchModels(
                    baseURL: baseURL,
                    apiKey: apiKey.isEmpty ? nil : apiKey
                )

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    availableModels = fetched
                    if !fetched.contains(modelID) {
                        modelID = fetched.first ?? ""
                    }
                    isLoadingModels = false
                }
                await FileLogger.shared.log("UI models loaded: count=\(fetched.count)", level: .debug)
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    availableModels = []
                    modelID = ""
                    modelsError = error.localizedDescription
                    isLoadingModels = false
                }
                await FileLogger.shared.log("UI models load failed: \(error.localizedDescription)", level: .error)
            }
        }
    }

    private func saveAction() {
        guard let provider = selectedProvider else { return }

        let cleanName = actionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanModel.isEmpty else { return }

        let providerID: String

        if provider.isCustom {
            let customProviderID = provider.id == BuiltinProviderID.custom.rawValue
                ? nil
                : provider.id
            let customProvider = LLMProviderStore.upsertCustomProvider(
                id: customProviderID,
                displayName: customProviderName,
                baseURL: customBaseURL
            )
            providerID = customProvider.id
        } else {
            providerID = provider.id
        }

        let cleanKey = providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanKey.isEmpty {
            try? KeychainService.deleteAPIKey(forProviderID: providerID)
        } else {
            try? KeychainService.saveAPIKey(cleanKey, forProviderID: providerID)
        }

        Task {
            await FileLogger.shared.log(
                "Action save: name=\(cleanName), providerID=\(providerID), model=\(cleanModel), auto=false",
                level: .info
            )
        }

        let resolvedSavePath = resolvedSaveToFilePath()

        if let action = actionToEdit {
            action.name = cleanName
            action.prompt = cleanPrompt
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

        dismiss()
    }

    private func insertPromptPlaceholder(_ placeholder: String) {
        let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            promptText = placeholder
            return
        }

        if promptText.hasSuffix("\n") {
            promptText += placeholder
            return
        }

        promptText += "\n\(placeholder)"
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Directory"

        if panel.runModal() == .OK, let url = panel.url {
            saveToFileDirectoryPath = url.path
        }
    }

    private func chooseExistingFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .text]
        panel.prompt = "Select File"

        if panel.runModal() == .OK, let url = panel.url {
            saveToFileExistingFilePath = url.path
        }
    }

    private func resolvedSaveToFilePath() -> String? {
        let rawPath = saveToFileMode == .newFile ? saveToFileDirectoryPath : saveToFileExistingFilePath
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

#Preview {
    AddActionView(actionToEdit: nil)
        .modelContainer(for: PostProcessingAction.self, inMemory: true)
}
