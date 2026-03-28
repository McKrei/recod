import Foundation
import SwiftData
import Testing
@testable import Recod

@Suite("RecordingPersistenceService", .serialized)
@MainActor
struct RecordingPersistenceServiceTests {
    private struct TestStore {
        let container: ModelContainer
        let context: ModelContext
    }

    private func makeStore() throws -> TestStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Recording.self, configurations: config)
        return TestStore(container: container, context: container.mainContext)
    }

    private func makeTempAudioURL(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try Data("audio".utf8).write(to: url)
        return url
    }

    @Test("createStreamingRecording persists draft metadata")
    func createStreamingRecordingPersistsDraftMetadata() throws {
        let service = RecordingPersistenceService.shared
        let store = try makeStore()
        let context = store.context
        let url = URL(fileURLWithPath: "/tmp/streaming-test.wav")

        let recording = try service.createStreamingRecording(
            for: url,
            engine: .parakeet,
            context: context
        )

        let saved = try context.fetch(FetchDescriptor<Recording>())
        #expect(saved.count == 1)
        #expect(saved.first?.id == recording.id)
        #expect(saved.first?.filename == "streaming-test.wav")
        #expect(saved.first?.transcriptionStatus == .streamingTranscription)
        #expect(saved.first?.transcriptionEngine == TranscriptionEngine.parakeet.rawValue)
    }

    @Test("resolveRecordingForFinalization reuses matching draft recording")
    func resolveRecordingForFinalizationReusesDraft() throws {
        let service = RecordingPersistenceService.shared
        let store = try makeStore()
        let context = store.context
        let draft = Recording(
            duration: 0,
            transcriptionStatus: .streamingTranscription,
            filename: "draft.wav",
            transcriptionEngine: TranscriptionEngine.whisperKit.rawValue
        )
        context.insert(draft)

        let resolved = try service.resolveRecordingForFinalization(
            from: draft,
            url: URL(fileURLWithPath: "/tmp/draft.wav"),
            duration: 12.5,
            context: context
        )

        let saved = try context.fetch(FetchDescriptor<Recording>())
        #expect(saved.count == 1)
        #expect(resolved.id == draft.id)
        #expect(resolved.duration == 12.5)
    }

    @Test("prepareForRetranscription clears previous output and queues recording")
    func prepareForRetranscriptionClearsPreviousOutput() throws {
        let service = RecordingPersistenceService.shared
        let store = try makeStore()
        let context = store.context
        let recording = Recording(
            duration: 10,
            transcription: "ready",
            liveTranscription: "live",
            transcriptionStatus: .completed,
            filename: "queued.wav",
            transcriptionEngine: TranscriptionEngine.whisperKit.rawValue,
            segments: [TranscriptionSegment(start: 0, end: 1, text: "segment")],
            postProcessedResults: []
        )
        context.insert(recording)

        service.prepareForRetranscription(recording, engine: .parakeet, context: context)

        #expect(recording.transcription == nil)
        #expect(recording.liveTranscription == nil)
        #expect(recording.segments == nil)
        #expect(recording.postProcessedResults == nil)
        #expect(recording.transcriptionStatus == .queued)
        #expect(recording.transcriptionEngine == TranscriptionEngine.parakeet.rawValue)
    }

    @Test("resolveRecordingForFinalization creates new recording when draft missing")
    func resolveRecordingForFinalizationCreatesNewRecording() throws {
        let service = RecordingPersistenceService.shared
        let store = try makeStore()
        let context = store.context
        let url = try makeTempAudioURL(named: "new-recording.wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let recording = try service.resolveRecordingForFinalization(
            from: nil,
            url: url,
            duration: 3.25,
            context: context
        )

        let saved = try context.fetch(FetchDescriptor<Recording>())
        #expect(saved.count == 1)
        #expect(recording.filename == "new-recording.wav")
        #expect(recording.duration == 3.25)
    }
}
