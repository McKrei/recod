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

    private func checkEngineReady(engine: TranscriptionEngine) -> Bool {
        switch engine {
        case .whisperKit:
            return whisperModelManager?.selectedModelId != nil
                && whisperModelManager?.getModelURL(for: whisperModelManager?.selectedModelId ?? "") != nil
        case .parakeet:
            return parakeetModelManager?.selectedModelId != nil
                && parakeetModelManager?.models.first(where: { $0.id == parakeetModelManager?.selectedModelId })?.isDownloaded == true
                && parakeetModelManager?.getVADModelPath() != nil
        }
    }

    private func preloadEngine(engine: TranscriptionEngine) {
        switch engine {
        case .whisperKit:
            if let id = whisperModelManager?.selectedModelId,
               let url = whisperModelManager?.getModelURL(for: id) {
                Task.detached(priority: .userInitiated) {
                    await TranscriptionService.shared.prepareModel(modelURL: url)
                }
            }
        case .parakeet:
            if let id = parakeetModelManager?.selectedModelId,
               let dir = parakeetModelManager?.getModelDirectory(for: id) {
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
                    let recording = Recording(
                        transcriptionStatus: .streamingTranscription,
                        filename: url.lastPathComponent,
                        transcriptionEngine: selectedEngine.rawValue
                    )
                    ctx.insert(recording)
                    try? ctx.save()
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
            if let id = whisperModelManager?.selectedModelId,
               let url = whisperModelManager?.getModelURL(for: id) {
                StreamingTranscriptionService.shared.startStreaming(
                    recording: recording, audioRecorder: audioRecorder, modelContext: context, modelURL: url
                )
            }
        case .parakeet:
            if let id = parakeetModelManager?.selectedModelId,
               let dir = parakeetModelManager?.getModelDirectory(for: id),
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
            let _ = ParakeetStreamingService.shared.flushAndCollectRemaining()
            ParakeetStreamingService.shared.stopStreaming()

            if let url = await audioRecorder.stopRecording() {
                let hasModel = checkEngineReady(engine: selectedEngine)
                if !hasModel {
                    OverlayState.shared.isVisible = false
                }
                await processFinalRecording(url: url, saveToClipboard: saveToClipboard, engine: selectedEngine)
            } else {
                OverlayState.shared.isVisible = false
            }
        }
    }

    private func processFinalRecording(url: URL, saveToClipboard: Bool, engine: TranscriptionEngine) async {
        guard let ctx = modelContext else {
            await FileLogger.shared.log("ModelContext not set in Orchestrator", level: .error)
            OverlayState.shared.isVisible = false
            return
        }

        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let filename = url.lastPathComponent

            let recording: Recording
            if let existing = self.streamingRecording, existing.filename == filename {
                recording = existing
                recording.duration = duration
                self.streamingRecording = nil
            } else {
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                let creationDate = attrs[.creationDate] as? Date ?? Date()
                recording = Recording(createdAt: creationDate, duration: duration, filename: filename)
                ctx.insert(recording)
            }

            try ctx.save()
            await FileLogger.shared.log("Saved new recording: \(filename)")

            await runBatchTranscription(recording: recording, url: url, context: ctx, engine: engine, saveToClipboard: saveToClipboard)
        } catch {
            await FileLogger.shared.log("Failed to save metadata: \(error)", level: .error)
            OverlayState.shared.isVisible = false
        }
    }

    private func runBatchTranscription(
        recording: Recording, url: URL, context: ModelContext, engine: TranscriptionEngine, saveToClipboard: Bool
    ) async {
        recording.transcriptionStatus = .transcribing
        try? context.save()

        do {
            let rawText: String
            let segments: [TranscriptionSegment]

            var rules: [ReplacementRule] = []
            let descriptor = FetchDescriptor<ReplacementRule>()
            do {
                rules = try context.fetch(descriptor)
            } catch {
                await FileLogger.shared.log("Failed to fetch replacement rules: \(error)", level: .error)
            }

            switch engine {
            case .whisperKit:
                guard let id = whisperModelManager?.selectedModelId,
                      let mUrl = whisperModelManager?.getModelURL(for: id) else { throw NSError(domain: "Recod", code: 1, userInfo: [NSLocalizedDescriptionKey: "WhisperKit model not ready"]) }
                (rawText, segments) = try await TranscriptionService.shared.transcribe(audioURL: url, modelURL: mUrl, rules: rules)
            case .parakeet:
                guard let id = parakeetModelManager?.selectedModelId,
                      let dir = parakeetModelManager?.getModelDirectory(for: id) else { throw NSError(domain: "Recod", code: 1, userInfo: [NSLocalizedDescriptionKey: "Parakeet model not ready"]) }
                (rawText, segments) = try await ParakeetTranscriptionService.shared.transcribe(audioURL: url, modelDir: dir, rules: rules)
            }

            recording.segments = segments

            var finalText = rawText
            if !rules.isEmpty {
                await FileLogger.shared.log("Applying \(rules.count) replacement rules...")
                finalText = TextReplacementService.applyReplacements(text: rawText, rules: rules)
            }

            recording.transcription = finalText
            recording.transcriptionStatus = .completed
            try context.save()

            await FileLogger.shared.log("Transcription (\(engine.displayName)) completed for: \(url.lastPathComponent)")
            await OverlayState.shared.showSuccess()

            Task {
                await ClipboardService.shared.insertText(finalText, preserveClipboard: !saveToClipboard)
            }
        } catch {
            recording.transcriptionStatus = .failed
            try? context.save()
            await FileLogger.shared.log("Transcription failed: \(error)", level: .error)
            await OverlayState.shared.showError()
        }
    }

    public func revealRecordings() {
        audioRecorder.revealRecordingsInFinder()
    }
}
