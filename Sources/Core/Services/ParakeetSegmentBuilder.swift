// Sources/Core/Services/ParakeetSegmentBuilder.swift

import Foundation

/// Converts BPE token-level timestamps from sherpa-onnx Parakeet output
/// into word-level groups, then sentence-level `TranscriptionSegment`s.
///
/// Parakeet TDT uses SentencePiece BPE: tokens starting with "▁" (U+2581)
/// indicate word boundaries. Sentence boundaries are detected by
/// terminal punctuation (. ? !).
struct ParakeetSegmentBuilder {

    // MARK: - Public API

    /// Merges BPE tokens into segments split on sentence-ending punctuation.
    ///
    /// - Parameters:
    ///   - tokens: BPE token strings (e.g., ["▁Hello", ",", "▁my", "▁name"])
    ///   - timestamps: Start time for each token (seconds from audio start)
    ///   - durations: Duration of each token (seconds, TDT-specific). May be empty.
    ///   - timeOffset: Global offset added to all timestamps (for streaming chunks)
    /// - Returns: Array of `TranscriptionSegment`
    static func buildSegments(
        tokens: [String],
        timestamps: [Float],
        durations: [Float],
        timeOffset: TimeInterval = 0
    ) -> [TranscriptionSegment] {
        guard !tokens.isEmpty else { return [] }

        // Step 1: BPE tokens → words
        let words = mergeTokensToWords(tokens: tokens, timestamps: timestamps, durations: durations, timeOffset: timeOffset)
        guard !words.isEmpty else { return [] }

        // Step 2: Words → sentence segments
        return groupWordsToSegments(words: words)
    }

    // MARK: - Step 1: BPE → Words

    private struct WordSpan {
        var text: String
        var start: TimeInterval
        var end: TimeInterval
    }

    private static func mergeTokensToWords(
        tokens: [String],
        timestamps: [Float],
        durations: [Float],
        timeOffset: TimeInterval
    ) -> [WordSpan] {
        var words: [WordSpan] = []
        var currentWord = ""
        var wordStart: TimeInterval = 0
        var wordEnd: TimeInterval = 0

        for i in 0..<tokens.count {
            let token = tokens[i]
            let start = TimeInterval(i < timestamps.count ? timestamps[i] : 0) + timeOffset
            let duration = TimeInterval(i < durations.count ? durations[i] : 0.08)
            let end = start + duration

            // "▁" (U+2581) prefix = start of new word (SentencePiece convention)
            let isNewWord = token.hasPrefix("\u{2581}") || token.hasPrefix(" ")
            let cleanToken = token
                .replacingOccurrences(of: "\u{2581}", with: "")
                .trimmingCharacters(in: .whitespaces)

            guard !cleanToken.isEmpty else { continue }

            if isNewWord && !currentWord.isEmpty {
                // Save previous word
                words.append(WordSpan(text: currentWord, start: wordStart, end: wordEnd))
                currentWord = cleanToken
                wordStart = start
                wordEnd = end
            } else {
                if currentWord.isEmpty {
                    wordStart = start
                }
                currentWord += cleanToken
                wordEnd = end
            }
        }

        // Flush last word
        if !currentWord.isEmpty {
            words.append(WordSpan(text: currentWord, start: wordStart, end: wordEnd))
        }

        return words
    }

    // MARK: - Step 2: Words → Sentence Segments

    private static let sentenceEnders: Set<Character> = [".", "?", "!"]

    private static func groupWordsToSegments(words: [WordSpan]) -> [TranscriptionSegment] {
        var segments: [TranscriptionSegment] = []
        var segmentWords: [WordSpan] = []

        for word in words {
            segmentWords.append(word)

            // Check if word ends with sentence-ending punctuation
            if let lastChar = word.text.last, sentenceEnders.contains(lastChar) {
                if let segment = buildSegmentFromWords(segmentWords) {
                    segments.append(segment)
                }
                segmentWords = []
            }
        }

        // Remaining words without sentence ender → final segment
        if !segmentWords.isEmpty {
            if let segment = buildSegmentFromWords(segmentWords) {
                segments.append(segment)
            }
        }

        return segments
    }

    private static func buildSegmentFromWords(_ words: [WordSpan]) -> TranscriptionSegment? {
        guard let first = words.first, let last = words.last else { return nil }
        let text = words.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return TranscriptionSegment(start: first.start, end: last.end, text: text)
    }
}
