import Testing
import SwiftData
import Foundation
@testable import Recod

@Suite("DataBackupService Tests")
@MainActor
struct DataBackupServiceTests {

    private let customProvidersDefaultsKey = "llmCustomProviders"

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Recording.self, ReplacementRule.self, PostProcessingAction.self, configurations: config)
    }

    private func resetCustomProvidersStorage() {
        UserDefaults.standard.removeObject(forKey: customProvidersDefaultsKey)
    }
    
    @Test("Export correctly maps models to DTOs and handles formatting")
    func testExportData() throws {
        resetCustomProvidersStorage()
        defer { resetCustomProvidersStorage() }

        let container = try makeContainer()
        let context = container.mainContext
        
        let r1 = Recording(id: UUID(), createdAt: Date(), duration: 10, transcription: "Text 1", filename: "f1.m4a")
        let r2 = Recording(id: UUID(), createdAt: Date(), duration: 20, transcription: "", filename: "f2.m4a") // Should be skipped (empty)
        let rule = ReplacementRule(id: UUID(), textToReplace: "foo", replacementText: "bar", createdAt: Date(), weight: 1.5, useFuzzyMatching: true)
        let action = PostProcessingAction(name: "Fix", prompt: "Transcript:\n${output}", providerID: "openai", modelID: "gpt-4o-mini", isAutoEnabled: true)

        let postResult = PostProcessedResult(
            actionID: action.id,
            actionName: action.name,
            providerID: action.providerID,
            modelID: action.modelID,
            messages: [
                LLMMessage(role: .user, content: "Transcript:\nText 1"),
                LLMMessage(role: .assistant, content: "Processed Text 1")
            ]
        )
        r1.postProcessedResults = [postResult]
        
        context.insert(r1)
        context.insert(r2)
        context.insert(rule)
        context.insert(action)

        _ = LLMProviderStore.upsertCustomProvider(
            id: "provider-1",
            displayName: "My Local",
            baseURL: "http://localhost:11434/v1"
        )
        
        let data = try DataBackupService.shared.exportData(context: context)
        
        // Deserialize manually to verify
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)
        
        #expect(payload.version == 2)
        #expect(payload.recordings.count == 1)
        #expect(payload.recordings.first?.id == r1.id)
        #expect(payload.recordings.first?.transcription == "Text 1")
        #expect(payload.recordings.first?.postProcessedResults?.count == 1)
        #expect(payload.recordings.first?.postProcessedResults?.first?.outputText == "Processed Text 1")
        
        #expect(payload.rules.count == 1)
        #expect(payload.rules.first?.textToReplace == "foo")

        #expect(payload.postProcessingActions?.count == 1)
        #expect(payload.postProcessingActions?.first?.name == "Fix")
        #expect(payload.postProcessingActions?.first?.isAutoEnabled == true)

        #expect(payload.customProviders?.isEmpty == false)
    }
    
    @Test("Import prevents duplicates based on UUID and content logic")
    func testImportPreventsDuplicates() throws {
        resetCustomProvidersStorage()
        defer { resetCustomProvidersStorage() }

        let container = try makeContainer()
        let context = container.mainContext
        
        let baseDate = Date()
        
        // Prepare original context
        let r1 = Recording(id: UUID(), createdAt: baseDate, duration: 10, transcription: "Original Recording", filename: "f1.m4a")
        let rule = ReplacementRule(id: UUID(), textToReplace: "foo", replacementText: "bar", createdAt: baseDate, weight: 1.5, useFuzzyMatching: true)
        
        context.insert(r1)
        context.insert(rule)
        
        // Create Payload DTOs
        // 1. Exact Duplicate (UUID match)
        let dupRecDTO = RecordingDTO(id: r1.id, createdAt: baseDate, duration: 10, transcription: "Original Recording", segments: nil, postProcessedResults: nil)
        
        // 2. Content Duplicate (Different UUID, same time & text)
        let contentDupRecDTO = RecordingDTO(id: UUID(), createdAt: baseDate, duration: 5, transcription: "Original Recording", segments: nil, postProcessedResults: nil)
        
        // 3. New Recording
        let newRecDTO = RecordingDTO(id: UUID(), createdAt: baseDate.addingTimeInterval(10), duration: 20, transcription: "New Recording", segments: nil, postProcessedResults: nil)
        
        // 1. Exact Rule Duplicate (UUID match)
        let dupRuleDTO = ReplacementRuleDTO(id: rule.id, textToReplace: "foo", additionalIncorrectForms: [], replacementText: "bar", createdAt: baseDate, weight: 1.5, useFuzzyMatching: true)
        
        // 2. Content Rule Duplicate (Different UUID, same lowercased text)
        let contentDupRuleDTO = ReplacementRuleDTO(id: UUID(), textToReplace: "FOO", additionalIncorrectForms: [], replacementText: "BAR", createdAt: baseDate, weight: 1.5, useFuzzyMatching: true)
        
        // 3. New Rule
        let newRuleDTO = ReplacementRuleDTO(id: UUID(), textToReplace: "baz", additionalIncorrectForms: [], replacementText: "qux", createdAt: baseDate, weight: 1.5, useFuzzyMatching: true)
        
        let payload = BackupPayload(
            version: 2,
            exportDate: Date(),
            recordings: [dupRecDTO, contentDupRecDTO, newRecDTO],
            rules: [dupRuleDTO, contentDupRuleDTO, newRuleDTO],
            postProcessingActions: nil,
            customProviders: nil
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        
        // Perform Import
        let summary = try DataBackupService.shared.importData(from: data, context: context)
        
        // Verifications
        #expect(summary.recordingsImported == 1) // Only newRecDTO
        #expect(summary.recordingsSkipped == 2)  // dupRecDTO, contentDupRecDTO
        
        #expect(summary.rulesImported == 1) // Only newRuleDTO
        #expect(summary.rulesSkipped == 2)  // dupRuleDTO, contentDupRuleDTO
        
        let finalRecords = try context.fetch(FetchDescriptor<Recording>())
        #expect(finalRecords.count == 2)
        
        // Ensure imported recording has isFileDeleted = true
        let importedRecord = finalRecords.first { $0.id == newRecDTO.id }
        #expect(importedRecord != nil)
        #expect(importedRecord?.isFileDeleted == true)
    }

    @Test("Import includes actions/providers, keeps single auto-enabled action")
    func testImportActionsProvidersAndSingleAutoRule() throws {
        resetCustomProvidersStorage()
        defer { resetCustomProvidersStorage() }

        let container = try makeContainer()
        let context = container.mainContext
        let baseDate = Date()

        let existingAuto = PostProcessingAction(
            id: UUID(),
            name: "Existing Auto",
            prompt: "Transcript:\n${output}",
            providerID: "openai",
            modelID: "gpt-4o-mini",
            isAutoEnabled: true,
            createdAt: baseDate
        )
        context.insert(existingAuto)

        let importedActions = [
            PostProcessingActionDTO(
                id: UUID(),
                name: "Imported Auto",
                prompt: "Transcript:\n${output}",
                providerID: "provider-imported",
                modelID: "model-1",
                isAutoEnabled: true,
                hotkey: nil,
                sortOrder: 0,
                createdAt: baseDate.addingTimeInterval(1)
            ),
            PostProcessingActionDTO(
                id: UUID(),
                name: "Imported Manual",
                prompt: "Transcript:\n${output}",
                providerID: "provider-imported",
                modelID: "model-2",
                isAutoEnabled: false,
                hotkey: nil,
                sortOrder: 1,
                createdAt: baseDate.addingTimeInterval(2)
            )
        ]

        let providers = [
            LLMProvider(
                id: "provider-imported",
                displayName: "Imported Local",
                baseURL: "http://localhost:11434/v1",
                isCustom: true,
                defaultModels: []
            )
        ]

        let payload = BackupPayload(
            version: 2,
            exportDate: Date(),
            recordings: [],
            rules: [],
            postProcessingActions: importedActions,
            customProviders: providers
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let summary = try DataBackupService.shared.importData(from: data, context: context)
        #expect(summary.actionsImported == 2)
        #expect(summary.customProvidersImported == 1)

        let allActions = try context.fetch(FetchDescriptor<PostProcessingAction>())
        #expect(allActions.count == 3)

        let autoCount = allActions.filter(\.isAutoEnabled).count
        #expect(autoCount == 1)

        #expect(allActions.contains(where: { $0.name == "Existing Auto" && $0.isAutoEnabled }))
        #expect(allActions.contains(where: { $0.name == "Imported Auto" && $0.isAutoEnabled == false }))

        let importedProviders = LLMProviderStore.loadCustomProviders()
        #expect(importedProviders.contains(where: { $0.id == "provider-imported" }))
    }
}
