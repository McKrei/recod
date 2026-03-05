import Foundation
import SwiftData

@MainActor
final class PostProcessingService {
    static let shared = PostProcessingService()

    private init() {}

    func runAction(_ action: PostProcessingAction, on recording: Recording, context: ModelContext) async throws {
        guard let sourceText = recording.transcription, !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await FileLogger.shared.log("Post-processing skipped: empty transcription for recording=\(recording.id)", level: .warning)
            return
        }

        await FileLogger.shared.log(
            "Post-processing action start: action=\(action.name), provider=\(action.providerID), model=\(action.modelID)",
            level: .info
        )

        let finalPrompt = action.prompt.isEmpty ? "Transcript:\n${output}" : action.prompt
        let outputWithTimestamps = formatOutputWithTimestamps(for: recording, fallbackText: sourceText)
        let userText = finalPrompt
            .replacingOccurrences(of: "${output_with_timestamps}", with: outputWithTimestamps)
            .replacingOccurrences(of: "${output}", with: sourceText)
        let inputMessages = [
            LLMMessage(role: .system, content: "You are a text post-processor. Return only final transformed text."),
            LLMMessage(role: .user, content: userText)
        ]

        let assistant = try await LLMService.shared.complete(
            messages: inputMessages,
            providerID: action.providerID,
            modelID: action.modelID
        )

        let normalizedInput = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOutput = assistant.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = normalizedInput != normalizedOutput
        let preview = String(normalizedOutput.prefix(160)).replacingOccurrences(of: "\n", with: " ")

        var results = recording.postProcessedResults ?? []
        results.append(
            PostProcessedResult(
                actionID: action.id,
                actionName: action.name,
                providerID: action.providerID,
                modelID: action.modelID,
                messages: inputMessages + [assistant]
            )
        )

        recording.postProcessedResults = results
        try context.save()

        if action.saveToFileEnabled, !normalizedOutput.isEmpty {
            await FileOutputService.shared.saveText(normalizedOutput, for: action)
        }

        await FileLogger.shared.log(
            "Post-processing action success: action=\(action.name), outputChars=\(assistant.content.count), changed=\(changed), outputPreview=\(preview)",
            level: .info
        )
    }

    func runAllAutoEnabled(on recording: Recording, context: ModelContext, actions: [PostProcessingAction]) async -> String? {
        let enabled = actions.filter(\.isAutoEnabled)
        if enabled.isEmpty {
            await FileLogger.shared.log("Post-processing skipped: no auto-enabled actions", level: .debug)
            return nil
        }

        let primaryAction = enabled.sorted(by: { $0.createdAt > $1.createdAt }).first
        guard let action = primaryAction else { return nil }

        if enabled.count > 1 {
            await FileLogger.shared.log(
                "Multiple auto-enabled actions found (\(enabled.count)). Keeping only latest: \(action.name)",
                level: .warning
            )
            for item in enabled where item.id != action.id {
                item.isAutoEnabled = false
            }
            try? context.save()
        }

        await FileLogger.shared.log("Post-processing start: action=\(action.name)", level: .info)

        do {
            try await runAction(action, on: recording, context: context)
        } catch {
            await FileLogger.shared.log(
                "Post-processing action failed: action=\(action.name), error=\(error.localizedDescription)",
                level: .error
            )
            return nil
        }

        await FileLogger.shared.log("Post-processing finished", level: .info)
        return recording.postProcessedResults?
            .last(where: { $0.actionID == action.id })?
            .outputText
    }

    /// Manually run a specific action on a recording.
    /// Clears any existing post-processed result before running.
    func runManual(_ action: PostProcessingAction, on recording: Recording, context: ModelContext) async throws {
        guard let transcription = recording.transcription,
              !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await FileLogger.shared.log(
                "Manual post-processing skipped: empty transcription for recording=\(recording.id)",
                level: .warning
            )
            return
        }

        // Business rule: one post-processed result per recording.
        recording.postProcessedResults = nil
        try context.save()

        try await runAction(action, on: recording, context: context)
    }

    private func formatOutputWithTimestamps(for recording: Recording, fallbackText: String) -> String {
        guard let segments = recording.segments, !segments.isEmpty else {
            return fallbackText
        }

        let lines = segments.compactMap { segment -> String? in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return "[\(formatTimestamp(segment.start))] \(text)"
        }

        if lines.isEmpty {
            return fallbackText
        }

        return lines.joined(separator: "\n")
    }

    private func formatTimestamp(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
