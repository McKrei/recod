import Foundation
import SwiftData
import Testing
@testable import Recod

@Suite("Recording Pipeline & Retranscription", .serialized)
@MainActor
struct RecordingPipelineCoordinatorTests {
    private struct TestStore {
        let container: ModelContainer
        let context: ModelContext
    }

    private func makeStore() throws -> TestStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Recording.self,
            ReplacementRule.self,
            PostProcessingAction.self,
            configurations: config
        )
        return TestStore(container: container, context: container.mainContext)
    }

    @Test("Batch finalization applies replacements, runs post-processing, and leaves clipboard untouched")
    func processBatchResultAppliesReplacementAndCompletes() async throws {
        let store = try makeStore()
        let recording = Recording(filename: "batch.wav")
        store.context.insert(recording)

        let rule = ReplacementRule(
            textToReplace: "foo",
            replacementText: "bar",
            useFuzzyMatching: false
        )
        let action = PostProcessingAction(
            name: "Cleanup",
            prompt: "${output}",
            providerID: "provider",
            modelID: "model",
            isAutoEnabled: true
        )

        var clipboardWrites: [(String, Bool)] = []
        let pipeline = RecordingFinalizationPipeline(
            fetchReplacementRules: { _ in [rule] },
            fetchPostProcessingActions: { _ in [action] },
            runAutoPostProcessing: { currentRecording, _, actions in
                #expect(currentRecording.transcription == "bar")
                #expect(actions.count == 1)
                return "baz"
            },
            insertClipboardText: { text, preserveClipboard in
                clipboardWrites.append((text, preserveClipboard))
            },
            showOverlayError: {},
            showOverlaySuccess: {},
            updateOverlayStatus: { _ in }
        )

        await pipeline.processBatchResult(
            recording: recording,
            text: "foo",
            segments: [TranscriptionSegment(start: 0, end: 1, text: "foo")],
            context: store.context
        )

        #expect(recording.transcription == "bar")
        #expect(recording.transcriptionStatus == .completed)
        #expect(recording.segments?.count == 1)
        #expect(clipboardWrites.isEmpty)
    }

    @Test("Stopped Whisper finalization uses streaming result without requiring batch model")
    func finalizeStoppedRecordingUsesStreamingWhisperResult() async throws {
        let store = try makeStore()
        let recording = Recording(
            liveTranscription: "  streamed text  ",
            transcriptionStatus: .streamingTranscription,
            filename: "streaming.wav",
            segments: [TranscriptionSegment(start: 0, end: 1, text: "streamed text")]
        )
        store.context.insert(recording)

        var clipboardWrites: [(String, Bool)] = []
        let pipeline = RecordingFinalizationPipeline(
            fetchReplacementRules: { _ in [] },
            fetchPostProcessingActions: { _ in [] },
            runAutoPostProcessing: { _, _, _ in nil },
            insertClipboardText: { text, preserveClipboard in
                clipboardWrites.append((text, preserveClipboard))
            },
            showOverlayError: {},
            showOverlaySuccess: {},
            updateOverlayStatus: { _ in }
        )

        await pipeline.finalizeStoppedRecording(
            recording: recording,
            url: URL(fileURLWithPath: "/tmp/streaming.wav"),
            context: store.context,
            engine: .whisperKit,
            saveToClipboard: false,
            whisperModelURL: nil,
            parakeetModelDir: nil,
            parakeetStreamingFinal: nil
        )

        await Task.yield()

        #expect(recording.transcription == "streamed text")
        #expect(recording.transcriptionStatus == .completed)
        #expect(clipboardWrites.count == 1)
        #expect(clipboardWrites.first?.0 == "streamed text")
        #expect(clipboardWrites.first?.1 == true)
    }

    @Test("Retranscription coordinator prepares recording and enqueues job with biasing snapshot")
    func retranscriptionCoordinatorPreparesAndEnqueues() async throws {
        let store = try makeStore()
        let recording = Recording(
            transcription: "ready",
            liveTranscription: "draft",
            transcriptionStatus: .completed,
            filename: "queued.wav",
            transcriptionEngine: TranscriptionEngine.whisperKit.rawValue,
            segments: [TranscriptionSegment(start: 0, end: 1, text: "segment")]
        )
        let rule = ReplacementRule(
            textToReplace: "OpenCode",
            replacementText: "OpenCode",
            weight: 2.0
        )
        store.context.insert(recording)
        store.context.insert(rule)

        let persistence = PersistenceSpy(recording: recording)
        let jobBox = JobCaptureBox()
        let coordinator = RetranscriptionCoordinator(
            persistenceService: persistence,
            finalizationPipeline: FinalizationSpy(),
            enqueueJob: { job in
                jobBox.job = job
            },
            cancelJob: { _ in }
        )

        coordinator.retranscribe(
            recording: recording,
            context: store.context,
            engine: .whisperKit,
            whisperModelURL: URL(fileURLWithPath: "/tmp/whisper-model"),
            parakeetModelDir: nil
        )

        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(persistence.preparedRecordingID == recording.id)
        #expect(recording.transcription == nil)
        #expect(recording.liveTranscription == nil)
        #expect(recording.transcriptionStatus == .queued)
        #expect(jobBox.job?.recordingID == recording.id)
        #expect(jobBox.job?.engine == .whisperKit)
        #expect(jobBox.job?.biasingEntries.count == 1)
        #expect(jobBox.job?.biasingEntries.first?.text == "OpenCode")
        #expect(jobBox.job?.whisperModelURL?.path == "/tmp/whisper-model")
    }

    @Test("Retranscription coordinator forwards completed batch result into finalization pipeline")
    func retranscriptionCoordinatorForwardsBatchCompletion() async throws {
        let store = try makeStore()
        let recording = Recording(filename: "done.wav")
        store.context.insert(recording)

        let persistence = PersistenceSpy(recording: recording)
        let finalization = FinalizationSpy()
        let coordinator = RetranscriptionCoordinator(
            persistenceService: persistence,
            finalizationPipeline: finalization,
            enqueueJob: { _ in },
            cancelJob: { _ in }
        )

        let segments = [TranscriptionSegment(start: 0, end: 1, text: "done")]
        await coordinator.handleBatchJobCompleted(
            recordingID: recording.id,
            text: "done",
            segments: segments,
            context: store.context
        )

        #expect(finalization.recordingID == recording.id)
        #expect(finalization.text == "done")
        #expect(finalization.segments == segments)
    }
}

@MainActor
private final class PersistenceSpy: RecordingPersistenceServing {
    var recording: Recording?
    var preparedRecordingID: UUID?

    init(recording: Recording?) {
        self.recording = recording
    }

    func createStreamingRecording(for url: URL, engine: TranscriptionEngine, context: ModelContext) throws -> Recording {
        let recording = Recording(
            transcriptionStatus: .streamingTranscription,
            filename: url.lastPathComponent,
            transcriptionEngine: engine.rawValue
        )
        self.recording = recording
        return recording
    }

    func resolveRecordingForFinalization(
        from draftRecording: Recording?,
        url: URL,
        duration: TimeInterval,
        context: ModelContext
    ) throws -> Recording {
        if let draftRecording {
            return draftRecording
        }
        let recording = Recording(duration: duration, filename: url.lastPathComponent)
        self.recording = recording
        return recording
    }

    func delete(_ recording: Recording, context: ModelContext) {}
    func save(_ context: ModelContext) throws {}
    func saveIfPossible(_ context: ModelContext) {}

    func updateStatus(
        _ status: Recording.TranscriptionStatus,
        for recording: Recording,
        context: ModelContext
    ) {
        recording.transcriptionStatus = status
    }

    func markFailed(for recording: Recording, context: ModelContext) {
        recording.transcriptionStatus = .failed
    }

    func markCancelled(for recording: Recording, context: ModelContext) {
        recording.transcriptionStatus = .cancelled
    }

    func fetchRecording(id: UUID, context: ModelContext) -> Recording? {
        recording?.id == id ? recording : nil
    }

    func prepareForRetranscription(
        _ recording: Recording,
        engine: TranscriptionEngine,
        context: ModelContext
    ) {
        preparedRecordingID = recording.id
        recording.transcription = nil
        recording.liveTranscription = nil
        recording.segments = nil
        recording.postProcessedResults = nil
        recording.transcriptionStatus = .queued
        recording.transcriptionEngine = engine.rawValue
    }
}

@MainActor
private final class FinalizationSpy: RecordingFinalizationPipelining {
    var recordingID: UUID?
    var text: String?
    var segments: [TranscriptionSegment] = []

    func processBatchResult(
        recording: Recording,
        text: String,
        segments: [TranscriptionSegment],
        context: ModelContext
    ) async {
        recordingID = recording.id
        self.text = text
        self.segments = segments
    }
}

private final class JobCaptureBox: @unchecked Sendable {
    var job: BatchTranscriptionJob?
}
