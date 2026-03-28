import Foundation
import SwiftData

// MARK: - Data Transfer Objects (DTO)

struct BackupPayload: Codable {
    let version: Int
    let exportDate: Date
    let recordings: [RecordingDTO]
    let rules: [ReplacementRuleDTO]
    let postProcessingActions: [PostProcessingActionDTO]?
    let customProviders: [LLMProvider]?
    let defaultPostProcessingSystemPrompt: String?
}

struct RecordingDTO: Codable {
    let id: UUID
    let createdAt: Date
    let duration: TimeInterval
    let transcription: String?
    let segments: [TranscriptionSegment]?
    let postProcessedResults: [PostProcessedResult]?
}

struct ReplacementRuleDTO: Codable {
    let id: UUID
    let textToReplace: String
    let additionalIncorrectForms: [String]
    let replacementText: String
    let createdAt: Date
    let weight: Float
    let useFuzzyMatching: Bool
}

struct PostProcessingActionDTO: Codable {
    let id: UUID
    let name: String
    let prompt: String
    let systemPrompt: String?
    let providerID: String
    let modelID: String
    let isAutoEnabled: Bool
    let hotkey: HotKeyShortcut?
    let sortOrder: Int
    let createdAt: Date
    let saveToFileEnabled: Bool?
    let saveToFileMode: String?
    let saveToFilePath: String?
    let saveToFileTemplate: String?
    let saveToFileSeparator: String?
    let saveToFileExtension: String?

    init(
        id: UUID,
        name: String,
        prompt: String,
        systemPrompt: String? = nil,
        providerID: String,
        modelID: String,
        isAutoEnabled: Bool,
        hotkey: HotKeyShortcut?,
        sortOrder: Int,
        createdAt: Date,
        saveToFileEnabled: Bool? = nil,
        saveToFileMode: String? = nil,
        saveToFilePath: String? = nil,
        saveToFileTemplate: String? = nil,
        saveToFileSeparator: String? = nil,
        saveToFileExtension: String? = nil
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.providerID = providerID
        self.modelID = modelID
        self.isAutoEnabled = isAutoEnabled
        self.hotkey = hotkey
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.saveToFileEnabled = saveToFileEnabled
        self.saveToFileMode = saveToFileMode
        self.saveToFilePath = saveToFilePath
        self.saveToFileTemplate = saveToFileTemplate
        self.saveToFileSeparator = saveToFileSeparator
        self.saveToFileExtension = saveToFileExtension
    }
}

struct ImportSummary: Equatable {
    var recordingsImported: Int = 0
    var recordingsSkipped: Int = 0
    var rulesImported: Int = 0
    var rulesSkipped: Int = 0
    var actionsImported: Int = 0
    var actionsSkipped: Int = 0
    var customProvidersImported: Int = 0
}

// MARK: - Backup Service

@MainActor
final class DataBackupService {
    static let shared = DataBackupService()
    
    private init() {}
    
    /// Exports all valid recordings and replacement rules to a JSON payload
    func exportData(context: ModelContext) throws -> Data {
        let allRecordings = try context.fetch(FetchDescriptor<Recording>())
        let allRules = try context.fetch(FetchDescriptor<ReplacementRule>())
        let allActions = try context.fetch(FetchDescriptor<PostProcessingAction>())

        let recordingDTOs = allRecordings
            .filter(isValidRecordingForExport)
            .map(recordingToDTO)

        let ruleDTOs = allRules.map(ruleToDTO)
        let actionDTOs = allActions.map(actionToDTO)
        
        let payload = BackupPayload(
            version: 3,
            exportDate: Date(),
            recordings: recordingDTOs,
            rules: ruleDTOs,
            postProcessingActions: actionDTOs,
            customProviders: LLMProviderStore.loadCustomProviders(),
            defaultPostProcessingSystemPrompt: AppState.shared.defaultPostProcessingSystemPrompt
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        return try encoder.encode(payload)
    }
    
    /// Imports a JSON payload, skipping duplicates and persisting new models to the context
    func importData(from data: Data, context: ModelContext) throws -> ImportSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let payload = try decoder.decode(BackupPayload.self, from: data)
        var summary = ImportSummary()
        
        let existingRecordings = try context.fetch(FetchDescriptor<Recording>())
        let existingRules = try context.fetch(FetchDescriptor<ReplacementRule>())
        let existingActions = try context.fetch(FetchDescriptor<PostProcessingAction>())
        
        for dto in payload.recordings {
            guard isValidRecordingDTOForImport(dto) else {
                summary.recordingsSkipped += 1
                continue
            }

            if hasRecordingDuplicate(dto: dto, existing: existingRecordings) {
                summary.recordingsSkipped += 1
            } else {
                let newRec = makeImportedRecording(from: dto)
                context.insert(newRec)
                summary.recordingsImported += 1
            }
        }
        
        for dto in payload.rules {
            if hasRuleDuplicate(dto: dto, existing: existingRules) {
                summary.rulesSkipped += 1
            } else {
                let newRule = makeImportedRule(from: dto)
                context.insert(newRule)
                summary.rulesImported += 1
            }
        }

        if let importedProviders = payload.customProviders, !importedProviders.isEmpty {
            summary.customProvidersImported = LLMProviderStore.mergeImportedCustomProviders(importedProviders)
        }

        if let importedDefaultPrompt = payload.defaultPostProcessingSystemPrompt,
           !importedDefaultPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AppState.shared.defaultPostProcessingSystemPrompt = importedDefaultPrompt
        }

        if let actionDTOs = payload.postProcessingActions {
            var hasEnabledAction = existingActions.contains(where: { $0.isAutoEnabled })

            for dto in actionDTOs {
                if hasActionDuplicate(dto: dto, existing: existingActions) {
                    summary.actionsSkipped += 1
                    continue
                }

                let canEnableAuto = dto.isAutoEnabled && !hasEnabledAction
                let newAction = makeImportedAction(from: dto, isAutoEnabled: canEnableAuto)
                context.insert(newAction)
                summary.actionsImported += 1

                if canEnableAuto {
                    hasEnabledAction = true
                }
            }
        }

        try context.save()
        return summary
    }

    // MARK: - Export Helpers

    private func isValidRecordingForExport(_ recording: Recording) -> Bool {
        guard let text = recording.transcription else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func recordingToDTO(_ recording: Recording) -> RecordingDTO {
        RecordingDTO(
            id: recording.id,
            createdAt: recording.createdAt,
            duration: recording.duration,
            transcription: recording.transcription,
            segments: recording.segments,
            postProcessedResults: recording.postProcessedResults
        )
    }

    private func ruleToDTO(_ rule: ReplacementRule) -> ReplacementRuleDTO {
        ReplacementRuleDTO(
            id: rule.id,
            textToReplace: rule.textToReplace,
            additionalIncorrectForms: rule.additionalIncorrectForms,
            replacementText: rule.replacementText,
            createdAt: rule.createdAt,
            weight: rule.weight,
            useFuzzyMatching: rule.useFuzzyMatching
        )
    }

    private func actionToDTO(_ action: PostProcessingAction) -> PostProcessingActionDTO {
        PostProcessingActionDTO(
            id: action.id,
            name: action.name,
            prompt: action.prompt,
            systemPrompt: action.trimmedSystemPrompt,
            providerID: action.providerID,
            modelID: action.modelID,
            isAutoEnabled: action.isAutoEnabled,
            hotkey: action.hotkey,
            sortOrder: action.sortOrder,
            createdAt: action.createdAt,
            saveToFileEnabled: action.saveToFileEnabled,
            saveToFileMode: action.saveToFileMode,
            saveToFilePath: action.saveToFilePath,
            saveToFileTemplate: action.saveToFileTemplate,
            saveToFileSeparator: action.saveToFileSeparator,
            saveToFileExtension: action.saveToFileExtension
        )
    }

    // MARK: - Import Helpers

    private func isValidRecordingDTOForImport(_ dto: RecordingDTO) -> Bool {
        guard let text = dto.transcription else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func hasRecordingDuplicate(dto: RecordingDTO, existing: [Recording]) -> Bool {
        let text = dto.transcription ?? ""
        return existing.contains { ext in
            if ext.id == dto.id { return true }
            let timeDiff = abs(ext.createdAt.timeIntervalSince1970 - dto.createdAt.timeIntervalSince1970)
            return timeDiff < 1.0 && ext.transcription == text
        }
    }

    private func hasRuleDuplicate(dto: ReplacementRuleDTO, existing: [ReplacementRule]) -> Bool {
        existing.contains { ext in
            ext.id == dto.id
                || (ext.textToReplace.lowercased() == dto.textToReplace.lowercased()
                    && ext.replacementText.lowercased() == dto.replacementText.lowercased())
        }
    }

    private func hasActionDuplicate(dto: PostProcessingActionDTO, existing: [PostProcessingAction]) -> Bool {
        existing.contains { ext in
            ext.id == dto.id
                || (ext.name.lowercased() == dto.name.lowercased()
                    && ext.providerID == dto.providerID
                    && ext.modelID == dto.modelID)
        }
    }

    private func makeImportedRecording(from dto: RecordingDTO) -> Recording {
        Recording(
            id: dto.id,
            createdAt: dto.createdAt,
            duration: dto.duration,
            transcription: dto.transcription,
            liveTranscription: nil,
            transcriptionStatus: .completed,
            filename: "imported_\(dto.id.uuidString).m4a",
            isFileDeleted: true,
            transcriptionEngine: "Imported",
            segments: dto.segments,
            postProcessedResults: dto.postProcessedResults
        )
    }

    private func makeImportedRule(from dto: ReplacementRuleDTO) -> ReplacementRule {
        ReplacementRule(
            id: dto.id,
            textToReplace: dto.textToReplace,
            additionalIncorrectForms: dto.additionalIncorrectForms,
            replacementText: dto.replacementText,
            createdAt: dto.createdAt,
            weight: dto.weight,
            useFuzzyMatching: dto.useFuzzyMatching
        )
    }

    private func makeImportedAction(from dto: PostProcessingActionDTO, isAutoEnabled: Bool) -> PostProcessingAction {
        PostProcessingAction(
            id: dto.id,
            name: dto.name,
            prompt: dto.prompt,
            systemPrompt: dto.systemPrompt,
            providerID: dto.providerID,
            modelID: dto.modelID,
            isAutoEnabled: isAutoEnabled,
            hotkey: dto.hotkey,
            sortOrder: dto.sortOrder,
            createdAt: dto.createdAt,
            saveToFileEnabled: dto.saveToFileEnabled ?? false,
            saveToFileMode: dto.saveToFileMode,
            saveToFilePath: dto.saveToFilePath,
            saveToFileTemplate: dto.saveToFileTemplate,
            saveToFileSeparator: dto.saveToFileSeparator,
            saveToFileExtension: dto.saveToFileExtension
        )
    }
}
