import Testing
import SwiftData
import Foundation
@testable import Recod

@Suite("History Delete Logic Tests")
@MainActor
struct HistoryLogicTests {
    
    // Simulate deleteRecording from HistoryView
    private func simulateDelete(recording: Recording, context: ModelContext) {
        if !recording.isFileDeleted {
            try? FileManager.default.removeItem(at: recording.fileURL)
        }
        context.delete(recording)
    }
    
    // Simulate deleteAudioOnly from HistoryView
    private func simulateDeleteAudioOnly(recording: Recording, context: ModelContext) {
        if !recording.isFileDeleted {
            try? FileManager.default.removeItem(at: recording.fileURL)
            recording.isFileDeleted = true
        }
        
        if recording.transcription.nilIfBlank == nil {
            context.delete(recording)
        }
    }
    
    // Simulate deleteAllFiles from HistoryView
    private func simulateDeleteAllFiles(allRecordings: [Recording], context: ModelContext) {
        for recording in allRecordings where !recording.isFileDeleted {
            try? FileManager.default.removeItem(at: recording.fileURL)
            recording.isFileDeleted = true
            
            if recording.transcription.nilIfBlank == nil {
                context.delete(recording)
            }
        }
    }
    
    private func createDummyFile(for recording: Recording) throws {
        let text = "dummy data"
        try text.write(to: recording.fileURL, atomically: true, encoding: .utf8)
    }
    
    @Test("deleteRecording completely deletes file and DB record")
    func testDeleteRecording() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Recording.self, configurations: config)
        let context = container.mainContext
        
        let recording = Recording(createdAt: .now, duration: 10, transcription: "Test", transcriptionStatus: .completed, filename: "test_del.m4a")
        context.insert(recording)
        
        try createDummyFile(for: recording)
        #expect(FileManager.default.fileExists(atPath: recording.fileURL.path))
        
        simulateDelete(recording: recording, context: context)
        
        #expect(!FileManager.default.fileExists(atPath: recording.fileURL.path))
        let records = try context.fetch(FetchDescriptor<Recording>())
        #expect(records.count == 0)
    }
    
    @Test("deleteAudioOnly keeps record if transcription exists")
    func testDeleteAudioOnly_WithTranscription() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Recording.self, configurations: config)
        let context = container.mainContext
        
        let recording = Recording(createdAt: .now, duration: 10, transcription: "Test", transcriptionStatus: .completed, filename: "test_audio.m4a")
        context.insert(recording)
        
        try createDummyFile(for: recording)
        
        simulateDeleteAudioOnly(recording: recording, context: context)
        
        #expect(!FileManager.default.fileExists(atPath: recording.fileURL.path))
        #expect(recording.isFileDeleted == true)
        
        let records = try context.fetch(FetchDescriptor<Recording>())
        #expect(records.count == 1)
    }
    
    @Test("deleteAudioOnly completely removes record if transcription is empty")
    func testDeleteAudioOnly_EmptyTranscription() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Recording.self, configurations: config)
        let context = container.mainContext
        
        let recording = Recording(createdAt: .now, duration: 10, transcription: "  \n  ", transcriptionStatus: .completed, filename: "test_audio_empty.m4a")
        context.insert(recording)
        
        try createDummyFile(for: recording)
        
        simulateDeleteAudioOnly(recording: recording, context: context)
        
        #expect(!FileManager.default.fileExists(atPath: recording.fileURL.path))
        
        let records = try context.fetch(FetchDescriptor<Recording>())
        #expect(records.count == 0)
    }
    
    @Test("deleteAllFiles correctly deletes files and cleans up empty transcription records")
    func testDeleteAllFiles() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Recording.self, configurations: config)
        let context = container.mainContext
        
        let rec1 = Recording(createdAt: .now, duration: 10, transcription: "T1", transcriptionStatus: .completed, filename: "test_all_1.m4a")
        let rec2 = Recording(createdAt: .now, duration: 20, transcription: "", transcriptionStatus: .completed, filename: "test_all_2.m4a")
        let rec3 = Recording(createdAt: .now, duration: 30, transcription: "T3", transcriptionStatus: .completed, filename: "test_all_3.m4a")
        rec3.isFileDeleted = true // Already deleted
        
        let allRecordings = [rec1, rec2, rec3]
        for r in allRecordings {
            context.insert(r)
            if !r.isFileDeleted {
                try createDummyFile(for: r)
            }
        }
        
        simulateDeleteAllFiles(allRecordings: allRecordings, context: context)
        
        #expect(!FileManager.default.fileExists(atPath: rec1.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: rec2.fileURL.path))
        
        let records = try context.fetch(FetchDescriptor<Recording>())
        #expect(records.count == 2) // rec2 should be deleted
        #expect(records.contains(where: { $0.id == rec1.id }))
        #expect(records.contains(where: { $0.id == rec3.id }))
        #expect(rec1.isFileDeleted == true)
    }
}
