import Foundation
import SwiftData
import AVFoundation
import SwiftUI
import Combine

/// Coordinates the high-level flow of the application:
/// Audio Recording -> Streaming -> File Saving -> Batch Transcription -> Clipboard Insertion
/// Removes complex orchestration logic from AppState.
@MainActor
final class RecordingOrchestrator: ObservableObject {
    public static let shared = RecordingOrchestrator()

    @Published public private(set) var isRecording = false
    private var isTransitioning = false
    
    private let audioRecorder = AudioRecorder()
    private let persistenceService = RecordingPersistenceService.shared
    private let finalizationPipeline = RecordingFinalizationPipeline.shared
    private let retranscriptionCoordinator = RetranscriptionCoordinator.shared
    private var streamingRecording: Recording?
    private var cancellables = Set<AnyCancellable>()

    // Dependencies injected at launch
    public var modelContext: ModelContext?
    public var whisperModelManager: WhisperModelManager?
    public var parakeetModelManager: ParakeetModelManager?

    private init() {
        setupBindings()
    }

    private func setupBindings() {
        audioRecorder.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] recording in
                self?.isRecording = recording
                if !recording {
                    OverlayState.shared.audioLevel = 0
                }
            }
            .store(in: &cancellables)

        audioRecorder.$audioLevel
            .receive(on: RunLoop.main)
            .sink { level in
                OverlayState.shared.audioLevel = level
            }
            .store(in: &cancellables)

        Task {
            await BatchTranscriptionQueue.shared.setCallbacks(
                onJobStarted: { [weak self] recordingID in
                    self?.retranscriptionCoordinator.handleBatchJobStarted(
                        recordingID: recordingID,
                        context: self?.modelContext
                    )
                },
                onJobCompleted: { [weak self] recordingID, text, segments in
                    await self?.retranscriptionCoordinator.handleBatchJobCompleted(
                        recordingID: recordingID,
                        text: text,
                        segments: segments,
                        context: self?.modelContext
                    )
                },
                onJobFailed: { [weak self] recordingID, error in
                    self?.retranscriptionCoordinator.handleBatchJobFailed(
                        recordingID: recordingID,
                        error: error,
                        context: self?.modelContext
                    )
                },
                onJobCancelled: { [weak self] recordingID in
                    self?.retranscriptionCoordinator.handleBatchJobCancelled(
                        recordingID: recordingID,
                        context: self?.modelContext
                    )
                }
            )
        }
    }

    public func prepareAudio() {
        audioRecorder.prepareAudio()
    }

    public func toggleRecording(
        recordSystemAudio: Bool,
        saveToClipboard: Bool,
        selectedEngine: TranscriptionEngine
    ) {
        if isRecording {
            stopRecording(saveToClipboard: saveToClipboard, selectedEngine: selectedEngine)
        } else {
            startRecording(recordSystemAudio: recordSystemAudio, selectedEngine: selectedEngine)
        }
    }

    public func cancelCurrentRecording() {
        guard !isTransitioning && isRecording else {
            Task { await FileLogger.shared.log("cancelCurrentRecording blocked: transitioning=\(isTransitioning)", level: .warning) }
            return
        }
        isTransitioning = true

        Task {
            defer { Task { @MainActor in self.isTransitioning = false } }

            OverlayState.shared.audioLevel = 0
            StreamingTranscriptionService.shared.stopStreaming()
            ParakeetStreamingService.shared.stopStreaming()

            let draftRecording = self.streamingRecording
            self.streamingRecording = nil

            if let url = await audioRecorder.stopRecording() {
                try? FileManager.default.removeItem(at: url)
            }

            if let context = modelContext, let draftRecording {
                persistenceService.delete(draftRecording, context: context)
            }

            OverlayState.shared.isVisible = false
            await FileLogger.shared.log("Recording cancelled by user")
        }
    }

    private func checkEngineReady(engine: TranscriptionEngine) -> Bool {
        switch engine {
        case .whisperKit:
            return whisperModelURL() != nil
        case .parakeet:
            return parakeetModelDirectory() != nil && parakeetModelManager?.getVADModelPath() != nil
        }
    }

    private func whisperModelURL() -> URL? {
        guard let whisperModelManager,
              let id = whisperModelManager.selectedModelId else {
            return nil
        }

        return whisperModelManager.getModelURL(for: id)
    }

    private func parakeetModelDirectory() -> URL? {
        guard let parakeetModelManager,
              let id = parakeetModelManager.selectedModelId,
              parakeetModelManager.models.first(where: { $0.id == id })?.isDownloaded == true else {
            return nil
        }

        return parakeetModelManager.getModelDirectory(for: id)
    }

    private func preloadEngine(engine: TranscriptionEngine) {
        switch engine {
        case .whisperKit:
            if let url = whisperModelURL() {
                Task.detached(priority: .userInitiated) {
                    await TranscriptionService.shared.prepareModel(modelURL: url)
                }
            }
        case .parakeet:
            if let dir = parakeetModelDirectory() {
                Task.detached(priority: .userInitiated) {
                    await ParakeetTranscriptionService.shared.prepareModel(modelDir: dir)
                }
            }
        }
    }

    private func startRecording(recordSystemAudio: Bool, selectedEngine: TranscriptionEngine) {
        guard !isTransitioning && !isRecording else {
            Task { await FileLogger.shared.log("startRecording blocked: transitioning=\(isTransitioning)", level: .warning) }
            return
        }
        isTransitioning = true

        Task {
            defer { Task { @MainActor in self.isTransitioning = false } }

            let engineReady = checkEngineReady(engine: selectedEngine)
            if !engineReady {
                await FileLogger.shared.log("Cannot start recording: \(selectedEngine.displayName) model not ready.", level: .error)
                await OverlayState.shared.showError()
                return
            }

            preloadEngine(engine: selectedEngine)

            do {
                OverlayState.shared.status = .recording
                audioRecorder.recordSystemAudio = recordSystemAudio
                try await audioRecorder.startRecording()
                OverlayState.shared.isVisible = true

                if let url = audioRecorder.currentRecordingURL, let ctx = modelContext {
                    let recording = try persistenceService.createStreamingRecording(
                        for: url,
                        engine: selectedEngine,
                        context: ctx
                    )
                    self.streamingRecording = recording

                    startStreaming(recording: recording, engine: selectedEngine, context: ctx)
                }
            } catch AudioRecorderError.bluetoothHFPDetected {
                await FileLogger.shared.log("Bluetooth HFP detected — recording aborted", level: .error)
                await OverlayState.shared.showError("Switch input to built-in mic\n(System Settings → Sound → Input)", durationNanoseconds: 4_000_000_000)
            } catch {
                await FileLogger.shared.log("Failed to start recording: \(error)", level: .error)
                await OverlayState.shared.showError()
            }
        }
    }

    private func startStreaming(recording: Recording, engine: TranscriptionEngine, context: ModelContext) {
        switch engine {
        case .whisperKit:
            if let url = whisperModelURL() {
                StreamingTranscriptionService.shared.startStreaming(
                    recording: recording, audioRecorder: audioRecorder, modelContext: context, modelURL: url
                )
            }
        case .parakeet:
            if let dir = parakeetModelDirectory(),
               let vad = parakeetModelManager?.getVADModelPath() {
                ParakeetStreamingService.shared.startStreaming(
                    recording: recording, audioRecorder: audioRecorder, modelContext: context, modelDir: dir, vadModelPath: vad
                )
            }
        }
    }

    private func stopRecording(saveToClipboard: Bool, selectedEngine: TranscriptionEngine) {
        guard !isTransitioning && isRecording else {
            Task { await FileLogger.shared.log("stopRecording blocked: transitioning=\(isTransitioning)", level: .warning) }
            return
        }
        isTransitioning = true

        Task {
            defer { Task { @MainActor in self.isTransitioning = false } }

            OverlayState.shared.audioLevel = 0
            OverlayState.shared.status = .transcribing

            StreamingTranscriptionService.shared.stopStreaming()
            var parakeetStreamingFinal: (String, [TranscriptionSegment])?
            if selectedEngine == .parakeet {
                parakeetStreamingFinal = await ParakeetStreamingService.shared.flushAndCollectRemaining()
            }
            ParakeetStreamingService.shared.stopStreaming()

            if let url = await audioRecorder.stopRecording() {
                let hasModel = checkEngineReady(engine: selectedEngine)
                if !hasModel {
                    OverlayState.shared.isVisible = false
                }
                await processFinalRecording(
                    url: url,
                    saveToClipboard: saveToClipboard,
                    engine: selectedEngine,
                    parakeetStreamingFinal: parakeetStreamingFinal
                )
            } else {
                OverlayState.shared.isVisible = false
            }
        }
    }

    private func processFinalRecording(
        url: URL,
        saveToClipboard: Bool,
        engine: TranscriptionEngine,
        parakeetStreamingFinal: (String, [TranscriptionSegment])?
    ) async {
        guard let ctx = modelContext else {
            await FileLogger.shared.log("ModelContext not set in Orchestrator", level: .error)
            OverlayState.shared.isVisible = false
            return
        }

        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let draftRecording = self.streamingRecording
            let recording = try persistenceService.resolveRecordingForFinalization(
                from: draftRecording,
                url: url,
                duration: duration,
                context: ctx
            )
            self.streamingRecording = nil

            await FileLogger.shared.log("Saved new recording: \(url.lastPathComponent)")

            await finalizationPipeline.finalizeStoppedRecording(
                recording: recording,
                url: url,
                context: ctx,
                engine: engine,
                saveToClipboard: saveToClipboard,
                whisperModelURL: whisperModelURL(),
                parakeetModelDir: parakeetModelDirectory(),
                parakeetStreamingFinal: parakeetStreamingFinal
            )
        } catch {
            await FileLogger.shared.log("Failed to save metadata: \(error)", level: .error)
            OverlayState.shared.isVisible = false
        }
    }

    public func revealRecordings() {
        audioRecorder.revealRecordingsInFinder()
    }

    // MARK: - Retranscribe

    /// Повторно транскрибирует существующую запись текущим движком.
    /// Не показывает overlay, не вставляет текст в буфер.
    public func retranscribe(recording: Recording) {
        guard let ctx = modelContext else {
            Task { await FileLogger.shared.log("retranscribe: modelContext not set", level: .error) }
            return
        }

        retranscriptionCoordinator.retranscribe(
            recording: recording,
            context: ctx,
            engine: AppState.shared.selectedEngine,
            whisperModelURL: whisperModelURL(),
            parakeetModelDir: parakeetModelDirectory()
        )
    }

    /// Manually triggers post-processing for a completed recording.
    /// Runs asynchronously, allowing multiple recordings to process independently.
    public func runManualPostProcessing(recording: Recording, action: PostProcessingAction) {
        guard recording.transcription.nilIfBlank != nil else {
            return
        }

        guard let context = modelContext else {
            Task { await FileLogger.shared.log("runManualPostProcessing: modelContext not set", level: .error) }
            return
        }

        Task { @MainActor in
            await FileLogger.shared.log(
                "Manual post-processing requested: recording=\(recording.id), action=\(action.name)",
                level: .info
            )

            recording.transcriptionStatus = .postProcessing
            try? context.save()

            do {
                try await PostProcessingService.shared.runManual(action, on: recording, context: context)
                recording.transcriptionStatus = .completed
                try? context.save()

                await FileLogger.shared.log(
                    "Manual post-processing completed: recording=\(recording.id), action=\(action.name)",
                    level: .info
                )
            } catch {
                recording.transcriptionStatus = .completed
                try? context.save()

                await FileLogger.shared.log(
                    "Manual post-processing failed: recording=\(recording.id), action=\(action.name), error=\(error.localizedDescription)",
                    level: .error
                )
            }
        }
    }

    public func cancelRetranscribe(recording: Recording) {
        retranscriptionCoordinator.cancelRetranscribe(recordingID: recording.id)
    }
}
