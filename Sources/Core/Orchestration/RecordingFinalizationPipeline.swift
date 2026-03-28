import Foundation
import SwiftData

@MainActor
final class RecordingFinalizationPipeline {
    typealias TranscriptionPayload = (text: String, segments: [TranscriptionSegment])

    static let shared = RecordingFinalizationPipeline()

    private let persistenceService: RecordingPersistenceService

    init(persistenceService: RecordingPersistenceService = .shared) {
        self.persistenceService = persistenceService
    }

    func finalizeStoppedRecording(
        recording: Recording,
        url: URL,
        context: ModelContext,
        engine: TranscriptionEngine,
        saveToClipboard: Bool,
        whisperModelURL: URL?,
        parakeetModelDir: URL?,
        parakeetStreamingFinal: TranscriptionPayload?
    ) async {
        persistenceService.updateStatus(.transcribing, for: recording, context: context)

        do {
            let rules = await fetchReplacementRules(context: context)
            let transcription = try await resolveFinalTranscription(
                for: engine,
                recording: recording,
                url: url,
                rules: rules,
                whisperModelURL: whisperModelURL,
                parakeetModelDir: parakeetModelDir,
                parakeetStreamingFinal: parakeetStreamingFinal
            )

            try await applyTranscriptionResult(
                transcription,
                to: recording,
                context: context,
                saveToClipboard: saveToClipboard,
                skipClipboard: false,
                showOverlayFeedback: true
            )

            await FileLogger.shared.log(
                "Transcription (\(engine.displayName)) completed for: \(url.lastPathComponent)"
            )
        } catch {
            persistenceService.markFailed(for: recording, context: context)
            await FileLogger.shared.log("Transcription failed: \(error)", level: .error)
            await OverlayState.shared.showError()
        }
    }

    func processBatchResult(
        recording: Recording,
        text: String,
        segments: [TranscriptionSegment],
        context: ModelContext
    ) async {
        do {
            try await applyTranscriptionResult(
                (text, segments),
                to: recording,
                context: context,
                saveToClipboard: false,
                skipClipboard: true,
                showOverlayFeedback: false
            )

            await FileLogger.shared.log(
                "Batch job completed: \(recording.filename), \(text.count) chars"
            )
        } catch {
            persistenceService.markFailed(for: recording, context: context)
            await FileLogger.shared.log(
                "Batch post-processing failed: \(recording.filename), error=\(error.localizedDescription)",
                level: .error
            )
        }
    }

    private func applyTranscriptionResult(
        _ transcription: TranscriptionPayload,
        to recording: Recording,
        context: ModelContext,
        saveToClipboard: Bool,
        skipClipboard: Bool,
        showOverlayFeedback: Bool
    ) async throws {
        let rules = await fetchReplacementRules(context: context)

        recording.segments = transcription.segments

        var finalText = transcription.text
        if !rules.isEmpty {
            await FileLogger.shared.log("Applying \(rules.count) replacement rules...")
            finalText = TextReplacementService.applyReplacements(text: transcription.text, rules: rules)
        }

        recording.transcription = finalText
        await FileLogger.shared.log("Transcription text ready, checking post-processing actions...", level: .debug)

        let actions = await fetchPostProcessingActions(context: context)
        var textForClipboard = finalText
        let enabledCount = actions.filter { $0.isAutoEnabled }.count

        if enabledCount > 0 {
            persistenceService.updateStatus(.postProcessing, for: recording, context: context)
            if showOverlayFeedback {
                OverlayState.shared.status = .postProcessing
            }

            await FileLogger.shared.log(
                "Starting post-processing: \(enabledCount) auto-enabled action(s)",
                level: .info
            )

            let postProcessedText = await PostProcessingService.shared.runAllAutoEnabled(
                on: recording,
                context: context,
                actions: actions
            )

            if let postProcessedText {
                textForClipboard = postProcessedText
                await FileLogger.shared.log("Using post-processed text for clipboard insertion", level: .info)
            } else {
                await FileLogger.shared.log(
                    "Post-processing produced no output. Falling back to original transcription",
                    level: .warning
                )
            }
        } else {
            await FileLogger.shared.log("Post-processing skipped: no auto-enabled actions", level: .debug)
        }

        persistenceService.updateStatus(.completed, for: recording, context: context)

        if !skipClipboard {
            Task {
                await ClipboardService.shared.insertText(textForClipboard, preserveClipboard: !saveToClipboard)
            }
        }

        if showOverlayFeedback {
            await OverlayState.shared.showSuccess()
        }
    }

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
        whisperModelURL: URL?,
        parakeetModelDir: URL?,
        parakeetStreamingFinal: TranscriptionPayload?
    ) async throws -> TranscriptionPayload {
        switch engine {
        case .whisperKit:
            return try await resolveWhisperFinalTranscription(
                recording: recording,
                url: url,
                rules: rules,
                modelURL: whisperModelURL
            )
        case .parakeet:
            return try await resolveParakeetFinalTranscription(
                url: url,
                rules: rules,
                modelDir: parakeetModelDir,
                streamingFinal: parakeetStreamingFinal
            )
        }
    }

    private func resolveWhisperFinalTranscription(
        recording: Recording,
        url: URL,
        rules: [ReplacementRule],
        modelURL: URL?
    ) async throws -> TranscriptionPayload {
        if let streamedText = nonEmptyTrimmed(recording.liveTranscription) {
            let streamedSegments = recording.segments ?? []
            await FileLogger.shared.log(
                "Using streaming Whisper result for finalization (chars=\(streamedText.count), segments=\(streamedSegments.count))",
                level: .info
            )
            return (streamedText, streamedSegments)
        }

        guard let modelURL else {
            throw NSError(domain: "Recod", code: 1, userInfo: [NSLocalizedDescriptionKey: "WhisperKit model not ready"])
        }

        await FileLogger.shared.log(
            "Streaming Whisper result empty. Falling back to full-file batch transcription.",
            level: .warning
        )
        let result = try await TranscriptionService.shared.transcribe(audioURL: url, modelURL: modelURL, rules: rules)
        return (result.0, result.1)
    }

    private func resolveParakeetFinalTranscription(
        url: URL,
        rules: [ReplacementRule],
        modelDir: URL?,
        streamingFinal: TranscriptionPayload?
    ) async throws -> TranscriptionPayload {
        if let streamedText = nonEmptyTrimmed(streamingFinal?.text) {
            let streamedSegments = streamingFinal?.segments ?? []
            await FileLogger.shared.log(
                "Using streaming Parakeet result for finalization (chars=\(streamedText.count), segments=\(streamedSegments.count))",
                level: .info
            )
            return (streamedText, streamedSegments)
        }

        guard let modelDir else {
            throw NSError(domain: "Recod", code: 1, userInfo: [NSLocalizedDescriptionKey: "Parakeet model not ready"])
        }

        await FileLogger.shared.log(
            "Streaming Parakeet result empty. Falling back to full-file batch transcription.",
            level: .warning
        )
        let hotwords = rules.map { rule in
            ParakeetHotword(text: rule.textToReplace, weight: rule.weight)
        }
        let result = try await ParakeetTranscriptionService.shared.transcribe(
            audioURL: url,
            modelDir: modelDir,
            hotwords: hotwords
        )
        return (result.0, result.1)
    }

    private func nonEmptyTrimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
