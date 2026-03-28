import Foundation

enum PostProcessingPromptBuilder {
    static let outputPlaceholder = "${output}"
    static let outputWithTimestampsPlaceholder = "${output_with_timestamps}"
    static let supportedPlaceholders = [outputPlaceholder, outputWithTimestampsPlaceholder]

    static var defaultPrompt: String {
        PostProcessingPromptDefaults.userPrompt
    }

    static func resolvedPrompt(_ prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultPrompt : prompt
    }

    static func buildUserPrompt(
        prompt: String,
        sourceText: String,
        timestampedText: String? = nil
    ) -> String {
        let resolvedTimestampedText = normalizedTimestampedText(timestampedText, fallbackText: sourceText)
        return resolvedPrompt(prompt)
            .replacingOccurrences(of: outputWithTimestampsPlaceholder, with: resolvedTimestampedText)
            .replacingOccurrences(of: outputPlaceholder, with: sourceText)
    }

    static func formatOutputWithTimestamps(
        segments: [TranscriptionSegment]?,
        fallbackText: String
    ) -> String {
        guard let segments, !segments.isEmpty else {
            return fallbackText
        }

        let lines = segments.compactMap { segment -> String? in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return "[\(formatTimestamp(segment.start))] \(text)"
        }

        return lines.isEmpty ? fallbackText : lines.joined(separator: "\n")
    }

    static func insertPlaceholder(_ placeholder: String, into prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return placeholder
        }

        if prompt.hasSuffix("\n") {
            return prompt + placeholder
        }

        return prompt + "\n\(placeholder)"
    }

    private static func normalizedTimestampedText(_ timestampedText: String?, fallbackText: String) -> String {
        guard let timestampedText else {
            return fallbackText
        }

        let trimmed = timestampedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallbackText : timestampedText
    }

    private static func formatTimestamp(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
