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

    private typealias TranscriptionPayload = (text: String, segments: [TranscriptionSegment])

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

        Task {
            await BatchTranscriptionQueue.shared.setCallbacks(
                onJobStarted: { [weak self] recordingID in
                    self?.handleBatchJobStarted(recordingID: recordingID)
                },
                onJobCompleted: { [weak self] recordingID, text, segments in
                    await self?.handleBatchJobCompleted(recordingID: recordingID, text: text, segments: segments)
                },
                onJobFailed: { [weak self] recordingID, error in
                    self?.handleBatchJobFailed(recordingID: recordingID, error: error)
                },
                onJobCancelled: { [weak self] recordingID in
                    self?.handleBatchJobCancelled(recordingID: recordingID)
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
                context.delete(draftRecording)
                try? context.save()
            }

            OverlayState.shared.isVisible = false
            await FileLogger.shared.log("Recording cancelled by user")
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

            await runBatchTranscription(
                recording: recording,
                url: url,
                context: ctx,
                engine: engine,
                saveToClipboard: saveToClipboard,
                parakeetStreamingFinal: parakeetStreamingFinal
            )
        } catch {
            await FileLogger.shared.log("Failed to save metadata: \(error)", level: .error)
            OverlayState.shared.isVisible = false
        }
    }

    private func runBatchTranscription(
        recording: Recording,
        url: URL,
        context: ModelContext,
        engine: TranscriptionEngine,
        saveToClipboard: Bool,
        parakeetStreamingFinal: (String, [TranscriptionSegment])?,
        skipClipboard: Bool = false
    ) async {
        recording.transcriptionStatus = .transcribing
        try? context.save()

        do {
            let rules = await fetchReplacementRules(context: context)
            let transcription = try await resolveFinalTranscription(
                for: engine,
                recording: recording,
                url: url,
                rules: rules,
                parakeetStreamingFinal: parakeetStreamingFinal
            )

            recording.segments = transcription.segments

            var finalText = transcription.text
            if !rules.isEmpty {
                await FileLogger.shared.log("Applying \(rules.count) replacement rules...")
                finalText = TextReplacementService.applyReplacements(text: transcription.text, rules: rules)
            }

            recording.transcription = finalText
            await FileLogger.shared.log("Transcription text ready, checking post-processing actions...", level: .debug)

            let actions = await fetchPostProcessingActions(context: context)

            let enabledCount = actions.filter { $0.isAutoEnabled }.count
            var textForClipboard = finalText
            if enabledCount > 0 {
                OverlayState.shared.status = .postProcessing
                recording.transcriptionStatus = .postProcessing
                try? context.save()
                await FileLogger.shared.log("Starting post-processing: \(enabledCount) auto-enabled action(s)", level: .info)
                let postProcessedText = await PostProcessingService.shared.runAllAutoEnabled(on: recording, context: context, actions: actions)
                if let postProcessedText {
                    textForClipboard = postProcessedText
                    await FileLogger.shared.log("Using post-processed text for clipboard insertion", level: .info)
                } else {
                    await FileLogger.shared.log("Post-processing produced no output. Falling back to original transcription", level: .warning)
                }
            } else {
                await FileLogger.shared.log("Post-processing skipped: no auto-enabled actions", level: .debug)
            }

            recording.transcriptionStatus = .completed
            try context.save()

            await FileLogger.shared.log("Transcription (\(engine.displayName)) completed for: \(url.lastPathComponent)")
            
            // Вставляем текст сразу же, чтобы юзер не ждал конца анимации. 
            // Это запустится параллельно с отображением галочки.
            if !skipClipboard {
                Task {
                    await ClipboardService.shared.insertText(textForClipboard, preserveClipboard: !saveToClipboard)
                }
            }

            await OverlayState.shared.showSuccess()
        } catch {
            recording.transcriptionStatus = .failed
            try? context.save()
            await FileLogger.shared.log("Transcription failed: \(error)", level: .error)
            await OverlayState.shared.showError()
        }
    }

    // MARK: - Finalization Helpers

    private func fetchReplacementRules(context: ModelContext) async -> [ReplacementRule] {
        do {
            return try context.fetch(FetchDescriptor<ReplacementRule>())
        } catch {
            await FileLogger.shared.log("Failed to fetch replacement rules: \(error)", level: .error)
            return []
        }
    }

    private func fetchPostProcessingActions(context: ModelContext) async -> [PostProcessingAction] {
        do {
            let actions = try context.fetch(FetchDescriptor<PostProcessingAction>())
            await FileLogger.shared.log("Post-processing actions fetched: \(actions.count)", level: .debug)
            return actions
        } catch {
            await FileLogger.shared.log("Failed to fetch post-processing actions: \(error)", level: .error)
            return []
        }
    }

    private func resolveFinalTranscription(
        for engine: TranscriptionEngine,
        recording: Recording,
        url: URL,
        rules: [ReplacementRule],
        parakeetStreamingFinal: (String, [TranscriptionSegment])?
    ) async throws -> TranscriptionPayload {
        switch engine {
        case .whisperKit:
            return try await resolveWhisperFinalTranscription(recording: recording, url: url, rules: rules)
        case .parakeet:
            return try await resolveParakeetFinalTranscription(url: url, rules: rules, streamingFinal: parakeetStreamingFinal)
        }
    }

    private func resolveWhisperFinalTranscription(
        recording: Recording,
        url: URL,
        rules: [ReplacementRule]
    ) async throws -> TranscriptionPayload {
        if let streamedText = nonEmptyTrimmed(recording.liveTranscription) {
            let streamedSegments = recording.segments ?? []
            await FileLogger.shared.log(
                "Using streaming Whisper result for finalization (chars=\(streamedText.count), segments=\(streamedSegments.count))",
                level: .info
            )
            return (streamedText, streamedSegments)
        }

        guard let id = whisperModelManager?.selectedModelId,
              let modelURL = whisperModelManager?.getModelURL(for: id) else {
            throw NSError(domain: "Recod", code: 1, userInfo: [NSLocalizedDescriptionKey: "WhisperKit model not ready"])
        }

        await FileLogger.shared.log("Streaming Whisper result empty. Falling back to full-file batch transcription.", level: .warning)
        let result = try await TranscriptionService.shared.transcribe(audioURL: url, modelURL: modelURL, rules: rules)
        return (result.0, result.1)
    }

    private func resolveParakeetFinalTranscription(
        url: URL,
        rules: [ReplacementRule],
        streamingFinal: (String, [TranscriptionSegment])?
    ) async throws -> TranscriptionPayload {
        if let streamedText = nonEmptyTrimmed(streamingFinal?.0) {
            let streamedSegments = streamingFinal?.1 ?? []
            await FileLogger.shared.log(
                "Using streaming Parakeet result for finalization (chars=\(streamedText.count), segments=\(streamedSegments.count))",
                level: .info
            )
            return (streamedText, streamedSegments)
        }

        guard let id = parakeetModelManager?.selectedModelId,
              let modelDir = parakeetModelManager?.getModelDirectory(for: id) else {
            throw NSError(domain: "Recod", code: 1, userInfo: [NSLocalizedDescriptionKey: "Parakeet model not ready"])
        }

        await FileLogger.shared.log("Streaming Parakeet result empty. Falling back to full-file batch transcription.", level: .warning)
        let hotwords = rules.map { rule in
            ParakeetHotword(text: rule.textToReplace, weight: rule.weight)
        }
        let result = try await ParakeetTranscriptionService.shared.transcribe(audioURL: url, modelDir: modelDir, hotwords: hotwords)
        return (result.0, result.1)
    }

    private func nonEmptyTrimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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

        let engine = AppState.shared.selectedEngine
        let rules = (try? ctx.fetch(FetchDescriptor<ReplacementRule>())) ?? []
        let biasingEntries = rules.map {
            InferenceBiasingEntry(text: $0.textToReplace, weight: $0.weight)
        }

        let whisperModelURL: URL?
        let parakeetModelDir: URL?

        switch engine {
        case .whisperKit:
            whisperModelURL = whisperModelManager.flatMap {
                guard let id = $0.selectedModelId else { return nil }
                return $0.getModelURL(for: id)
            }
            parakeetModelDir = nil
        case .parakeet:
            whisperModelURL = nil
            parakeetModelDir = parakeetModelManager.flatMap {
                guard let id = $0.selectedModelId else { return nil }
                return $0.getModelDirectory(for: id)
            }
        }

        let modelAvailable: Bool
        switch engine {
        case .whisperKit:
            modelAvailable = whisperModelURL != nil
        case .parakeet:
            modelAvailable = parakeetModelDir != nil
        }

        guard modelAvailable else {
            Task { await FileLogger.shared.log("retranscribe: engine \(engine.displayName) not ready", level: .error) }
            recording.transcriptionStatus = .failed
            try? ctx.save()
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

        recording.transcription = nil
        recording.liveTranscription = nil
        recording.segments = nil
        recording.postProcessedResults = nil
        recording.transcriptionStatus = .queued
        recording.transcriptionEngine = engine.rawValue
        try? ctx.save()

        Task {
            await FileLogger.shared.log("Retranscribe enqueued: \(recording.filename), engine=\(engine.displayName)")
            await BatchTranscriptionQueue.shared.enqueue(job)
        }
    }

    /// Manually triggers post-processing for a completed recording.
    /// Runs asynchronously, allowing multiple recordings to process independently.
    public func runManualPostProcessing(recording: Recording, action: PostProcessingAction) {
        guard recording.transcription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
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
        let recordingID = recording.id
        Task {
            await BatchTranscriptionQueue.shared.cancel(recordingID: recordingID)
        }
    }

    // MARK: - Batch Queue Handlers

    private func handleBatchJobStarted(recordingID: UUID) {
        guard let ctx = modelContext,
              let recording = fetchRecording(id: recordingID, context: ctx) else {
            return
        }

        recording.transcriptionStatus = .transcribing
        try? ctx.save()

        Task {
            await FileLogger.shared.log("Batch job started: \(recording.filename)")
        }
    }

    private func handleBatchJobCompleted(recordingID: UUID, text: String, segments: [TranscriptionSegment]) async {
        guard let ctx = modelContext,
              let recording = fetchRecording(id: recordingID, context: ctx) else {
            return
        }

        let rules = await fetchReplacementRules(context: ctx)
        var finalText = text
        if !rules.isEmpty {
            finalText = TextReplacementService.applyReplacements(text: text, rules: rules)
        }

        recording.transcription = finalText
        recording.segments = segments
        recording.transcriptionStatus = .completed
        try? ctx.save()

        await FileLogger.shared.log("Batch job completed: \(recording.filename), \(finalText.count) chars")

        let actions = await fetchPostProcessingActions(context: ctx)
        let autoEnabledCount = actions.filter { $0.isAutoEnabled }.count
        if autoEnabledCount > 0 {
            recording.transcriptionStatus = .postProcessing
            try? ctx.save()

            _ = await PostProcessingService.shared.runAllAutoEnabled(on: recording, context: ctx, actions: actions)

            recording.transcriptionStatus = .completed
            try? ctx.save()
        }
    }

    private func handleBatchJobFailed(recordingID: UUID, error: Error) {
        guard let ctx = modelContext,
              let recording = fetchRecording(id: recordingID, context: ctx) else {
            return
        }

        recording.transcriptionStatus = .failed
        try? ctx.save()

        Task {
            await FileLogger.shared.log("Batch job failed: \(recording.filename), error=\(error.localizedDescription)", level: .error)
        }
    }

    private func handleBatchJobCancelled(recordingID: UUID) {
        guard let ctx = modelContext,
              let recording = fetchRecording(id: recordingID, context: ctx) else {
            return
        }

        recording.transcriptionStatus = .cancelled
        try? ctx.save()

        Task {
            await FileLogger.shared.log("Batch job cancelled: \(recording.filename)")
        }
    }

    private func fetchRecording(id: UUID, context: ModelContext) -> Recording? {
        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }
}
