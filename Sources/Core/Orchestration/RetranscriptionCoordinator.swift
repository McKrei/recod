import Foundation
import SwiftData

@MainActor
final class RetranscriptionCoordinator {
    typealias EnqueueJob = @Sendable (BatchTranscriptionJob) async -> Void
    typealias CancelJob = @Sendable (UUID) async -> Void

    static let shared = RetranscriptionCoordinator()

    private let persistenceService: any RecordingPersistenceServing
    private let finalizationPipeline: any RecordingFinalizationPipelining
    private let enqueueJob: EnqueueJob
    private let cancelJob: CancelJob

    init(
        persistenceService: any RecordingPersistenceServing = RecordingPersistenceService.shared,
        finalizationPipeline: any RecordingFinalizationPipelining = RecordingFinalizationPipeline.shared,
        enqueueJob: @escaping EnqueueJob = { job in
            BatchTranscriptionQueue.shared.enqueue(job)
        },
        cancelJob: @escaping CancelJob = { recordingID in
            await BatchTranscriptionQueue.shared.cancel(recordingID: recordingID)
        }
    ) {
        self.persistenceService = persistenceService
        self.finalizationPipeline = finalizationPipeline
        self.enqueueJob = enqueueJob
        self.cancelJob = cancelJob
    }

    func retranscribe(
        recording: Recording,
        context: ModelContext,
        engine: TranscriptionEngine,
        whisperModelURL: URL?,
        parakeetModelDir: URL?
    ) {
        let rules = (try? context.fetch(FetchDescriptor<ReplacementRule>())) ?? []
        let biasingEntries = rules.map {
            InferenceBiasingEntry(text: $0.textToReplace, weight: $0.weight)
        }

        let modelAvailable: Bool
        switch engine {
        case .whisperKit:
            modelAvailable = whisperModelURL != nil
        case .parakeet:
            modelAvailable = parakeetModelDir != nil
        }

        guard modelAvailable else {
            Task {
                await FileLogger.shared.log("retranscribe: engine \(engine.displayName) not ready", level: .error)
            }
            persistenceService.markFailed(for: recording, context: context)
            return
        }

        let job = BatchTranscriptionJob(
            recordingID: recording.id,
            audioURL: recording.fileURL,
            engine: engine,
            enqueuedAt: Date(),
            biasingEntries: biasingEntries,
            whisperModelURL: whisperModelURL,
            parakeetModelDir: parakeetModelDir
        )

        persistenceService.prepareForRetranscription(recording, engine: engine, context: context)

        Task {
            await FileLogger.shared.log(
                "Retranscribe enqueued: \(recording.filename), engine=\(engine.displayName)"
            )
            await enqueueJob(job)
        }
    }

    func cancelRetranscribe(recordingID: UUID) {
        Task {
            await cancelJob(recordingID)
        }
    }

    func handleBatchJobStarted(recordingID: UUID, context: ModelContext?) {
        guard let context,
              let recording = persistenceService.fetchRecording(id: recordingID, context: context) else {
            return
        }

        persistenceService.updateStatus(.transcribing, for: recording, context: context)

        Task {
            await FileLogger.shared.log("Batch job started: \(recording.filename)")
        }
    }

    func handleBatchJobCompleted(
        recordingID: UUID,
        text: String,
        segments: [TranscriptionSegment],
        context: ModelContext?
    ) async {
        guard let context,
              let recording = persistenceService.fetchRecording(id: recordingID, context: context) else {
            return
        }

        await finalizationPipeline.processBatchResult(
            recording: recording,
            text: text,
            segments: segments,
            context: context
        )
    }

    func handleBatchJobFailed(recordingID: UUID, error: Error, context: ModelContext?) {
        guard let context,
              let recording = persistenceService.fetchRecording(id: recordingID, context: context) else {
            return
        }

        persistenceService.markFailed(for: recording, context: context)

        Task {
            await FileLogger.shared.log(
                "Batch job failed: \(recording.filename), error=\(error.localizedDescription)",
                level: .error
            )
        }
    }

    func handleBatchJobCancelled(recordingID: UUID, context: ModelContext?) {
        guard let context,
              let recording = persistenceService.fetchRecording(id: recordingID, context: context) else {
            return
        }

        persistenceService.markCancelled(for: recording, context: context)

        Task {
            await FileLogger.shared.log("Batch job cancelled: \(recording.filename)")
        }
    }
}
