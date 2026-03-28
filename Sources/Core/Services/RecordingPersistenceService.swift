import Foundation
import SwiftData

@MainActor
final class RecordingPersistenceService {
    static let shared = RecordingPersistenceService()

    private init() {}

    func createStreamingRecording(
        for url: URL,
        engine: TranscriptionEngine,
        context: ModelContext
    ) throws -> Recording {
        let recording = Recording(
            transcriptionStatus: .streamingTranscription,
            filename: url.lastPathComponent,
            transcriptionEngine: engine.rawValue
        )
        context.insert(recording)
        try context.save()
        return recording
    }

    func resolveRecordingForFinalization(
        from draftRecording: Recording?,
        url: URL,
        duration: TimeInterval,
        context: ModelContext
    ) throws -> Recording {
        let filename = url.lastPathComponent

        if let draftRecording, draftRecording.filename == filename {
            draftRecording.duration = duration
            try context.save()
            return draftRecording
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let creationDate = attributes[.creationDate] as? Date ?? Date()
        let recording = Recording(createdAt: creationDate, duration: duration, filename: filename)
        context.insert(recording)
        try context.save()
        return recording
    }

    func delete(_ recording: Recording, context: ModelContext) {
        context.delete(recording)
        try? context.save()
    }

    func save(_ context: ModelContext) throws {
        try context.save()
    }

    func saveIfPossible(_ context: ModelContext) {
        try? context.save()
    }

    func updateStatus(
        _ status: Recording.TranscriptionStatus,
        for recording: Recording,
        context: ModelContext
    ) {
        recording.transcriptionStatus = status
        saveIfPossible(context)
    }

    func markFailed(for recording: Recording, context: ModelContext) {
        updateStatus(.failed, for: recording, context: context)
    }

    func markCancelled(for recording: Recording, context: ModelContext) {
        updateStatus(.cancelled, for: recording, context: context)
    }

    func fetchRecording(id: UUID, context: ModelContext) -> Recording? {
        let descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    func prepareForRetranscription(
        _ recording: Recording,
        engine: TranscriptionEngine,
        context: ModelContext
    ) {
        recording.transcription = nil
        recording.liveTranscription = nil
        recording.segments = nil
        recording.postProcessedResults = nil
        recording.transcriptionStatus = .queued
        recording.transcriptionEngine = engine.rawValue
        saveIfPossible(context)
    }
}
