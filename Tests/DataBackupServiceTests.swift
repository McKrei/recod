import Testing
import SwiftData
import Foundation
@testable import Recod

@Suite("DataBackupService Tests")
@MainActor
struct DataBackupServiceTests {
    
    @Test("Export correctly maps models to DTOs and handles formatting")
    func testExportData() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Recording.self, ReplacementRule.self, configurations: config)
        let context = container.mainContext
        
        let r1 = Recording(id: UUID(), createdAt: Date(), duration: 10, transcription: "Text 1", filename: "f1.m4a")
        let r2 = Recording(id: UUID(), createdAt: Date(), duration: 20, transcription: "", filename: "f2.m4a") // Should be skipped (empty)
        let rule = ReplacementRule(id: UUID(), textToReplace: "foo", replacementText: "bar", createdAt: Date(), weight: 1.5, useFuzzyMatching: true)
        
        context.insert(r1)
        context.insert(r2)
        context.insert(rule)
        
        let data = try DataBackupService.shared.exportData(context: context)
        
        // Deserialize manually to verify
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)
        
        #expect(payload.version == 1)
        #expect(payload.recordings.count == 1)
        #expect(payload.recordings.first?.id == r1.id)
        #expect(payload.recordings.first?.transcription == "Text 1")
        
        #expect(payload.rules.count == 1)
        #expect(payload.rules.first?.textToReplace == "foo")
    }
    
    @Test("Import prevents duplicates based on UUID and content logic")
    func testImportPreventsDuplicates() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Recording.self, ReplacementRule.self, configurations: config)
        let context = container.mainContext
        
        let baseDate = Date()
        
        // Prepare original context
        let r1 = Recording(id: UUID(), createdAt: baseDate, duration: 10, transcription: "Original Recording", filename: "f1.m4a")
        let rule = ReplacementRule(id: UUID(), textToReplace: "foo", replacementText: "bar", createdAt: baseDate, weight: 1.5, useFuzzyMatching: true)
        
        context.insert(r1)
        context.insert(rule)
        
        // Create Payload DTOs
        // 1. Exact Duplicate (UUID match)
        let dupRecDTO = RecordingDTO(id: r1.id, createdAt: baseDate, duration: 10, transcription: "Original Recording", segments: nil)
        
        // 2. Content Duplicate (Different UUID, same time & text)
        let contentDupRecDTO = RecordingDTO(id: UUID(), createdAt: baseDate, duration: 5, transcription: "Original Recording", segments: nil)
        
        // 3. New Recording
        let newRecDTO = RecordingDTO(id: UUID(), createdAt: baseDate.addingTimeInterval(10), duration: 20, transcription: "New Recording", segments: nil)
        
        // 1. Exact Rule Duplicate (UUID match)
        let dupRuleDTO = ReplacementRuleDTO(id: rule.id, textToReplace: "foo", additionalIncorrectForms: [], replacementText: "bar", createdAt: baseDate, weight: 1.5, useFuzzyMatching: true)
        
        // 2. Content Rule Duplicate (Different UUID, same lowercased text)
        let contentDupRuleDTO = ReplacementRuleDTO(id: UUID(), textToReplace: "FOO", additionalIncorrectForms: [], replacementText: "BAR", createdAt: baseDate, weight: 1.5, useFuzzyMatching: true)
        
        // 3. New Rule
        let newRuleDTO = ReplacementRuleDTO(id: UUID(), textToReplace: "baz", additionalIncorrectForms: [], replacementText: "qux", createdAt: baseDate, weight: 1.5, useFuzzyMatching: true)
        
        let payload = BackupPayload(
            version: 1,
            exportDate: Date(),
            recordings: [dupRecDTO, contentDupRecDTO, newRecDTO],
            rules: [dupRuleDTO, contentDupRuleDTO, newRuleDTO]
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
}
