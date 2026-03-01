import Foundation
@preconcurrency import WhisperKit
import AVFoundation

@MainActor
final class TranscriptionService {
    static let shared = TranscriptionService()

    private var whisperKit: WhisperKit?
    public var activeWhisperKit: WhisperKit? { return whisperKit }
    private var currentModelURL: URL?

    private init() {}

    func prepareModel(modelURL: URL) async {
        if currentModelURL == modelURL && whisperKit != nil {
            return
        }

        await FileLogger.shared.log("Pre-loading WhisperKit model: \(modelURL.lastPathComponent)")
        let start = Date()

        do {
            whisperKit = try await WhisperKit(modelFolder: modelURL.path(percentEncoded: false))
            currentModelURL = modelURL

            let duration = Date().timeIntervalSince(start)
            await FileLogger.shared.log(String(format: "WhisperKit (CoreML) loaded and cached: %.2fs", duration))
        } catch {
            await FileLogger.shared.log("Failed to load WhisperKit: \(error)", level: .error)
            whisperKit = nil
            currentModelURL = nil
        }
    }

    /// Transcribes the given audio file using the specified WhisperKit model.
    /// - Parameters:
    ///   - audioURL: URL to the local audio file (WAV 16kHz mono recommended).
    ///   - modelURL: URL to the folder containing the WhisperKit CoreML model.
    /// - Returns: A tuple containing the joined cleaned transcription text and an array of timestamped segments.
    func transcribe(audioURL: URL, modelURL: URL, rules: [ReplacementRule] = []) async throws -> (String, [TranscriptionSegment]) {
        let startTime = Date()
        await FileLogger.shared.log("--- WhisperKit Transcription Start ---")

        if whisperKit == nil || currentModelURL != modelURL {
            await prepareModel(modelURL: modelURL)
        }

        guard let kit = whisperKit else {
            throw NSError(domain: "TranscriptionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "WhisperKit not initialized"])
        }

        // Wait for file to be ready (e.g. after recording finishes and writes to disk)
        let frameCount = try await waitForFileReady(url: audioURL)
        await FileLogger.shared.log("Audio file verified and ready (\(frameCount) frames)")

        await FileLogger.shared.log("Starting WhisperKit inference...")
        let inferStart = Date()

        // 1. Language Detection (Two-pass logic)
        let detectionResult = try await kit.detectLanguage(audioPath: audioURL.path)
        let detectedLang = detectionResult.language
        let prob = detectionResult.langProbs[detectedLang] ?? 0.0
        await FileLogger.shared.log("Detected language: \(detectedLang) (prob: \(prob))")

        // 2. Transcription with detected language
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = detectedLang
        options.temperature = 0.0

        // Context Biasing (Word Boosting) for WhisperKit
        if !rules.isEmpty {
            var promptTokens: [Int] = []
            
            for rule in rules {
                // WhisperKit prefers words starting with a space to match mid-sentence tokens
                let words = [" " + rule.textToReplace, rule.textToReplace]
                for word in words {
                    if let tokenizer = kit.tokenizer {
                        let encoded = tokenizer.encode(text: word)
                        if !encoded.isEmpty {
                            // We repeat the token sequence based on its weight to artificially "boost" it
                            // Whisper promptTokens limit is around 224, so we need to be careful
                            let repeatCount = Int(max(1.0, rule.weight))
                            for _ in 0..<repeatCount {
                                promptTokens.append(contentsOf: encoded)
                            }
                        }
                    }
                }
            }
            
            // Limit to max 224 tokens (Whisper's prompt limit)
            if promptTokens.count > 224 {
                promptTokens = Array(promptTokens.suffix(224))
            }
            
            if !promptTokens.isEmpty {
                options.promptTokens = promptTokens
                await FileLogger.shared.log("WhisperKit Context Biasing: Injected \(promptTokens.count) tokens from user dictionary.")
            }
        }

        let results = try await kit.transcribe(audioPath: audioURL.path, decodeOptions: options)

        // Process results: join text and clean up special tokens
        let rawJoinedText = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = cleanTranscriptionText(rawJoinedText)

        // Extract segments from TranscriptionResult.segments and clean their text
        let segments = results.flatMap { result in
            result.segments.map { segment in
                TranscriptionSegment(
                    id: UUID(),
                    start: Double(segment.start),
                    end: Double(segment.end),
                    text: cleanTranscriptionText(segment.text)
                )
            }
        }

        let inferDuration = Date().timeIntervalSince(inferStart)
        let totalDuration = Date().timeIntervalSince(startTime)

        await FileLogger.shared.log(String(format: "Inference completed: %.2fs", inferDuration))
        await FileLogger.shared.log(String(format: "Total process time: %.2fs", totalDuration))
        await FileLogger.shared.log("--- Transcription End ---")

        return (text, segments)
    }

    /// Removes WhisperKit special tokens like <|startoftranscript|>, <|en|>, <|transcribe|>, etc.
    /// These tokens sometimes appear in the output text and segments.
    private func cleanTranscriptionText(_ text: String) -> String {
        let pattern = "<\\|.*?\\|>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let cleaned = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func waitForFileReady(url: URL) async throws -> AVAudioFramePosition {
        var lastError: Error?

        for i in 0..<12 {
            do {
                let file = try AVAudioFile(forReading: url)
                let length = file.length
                if length > 0 {
                    return length
                }
            } catch {
                lastError = error
            }

            try? await Task.sleep(nanoseconds: 100_000_000 * UInt64(i + 1))
        }

        await FileLogger.shared.log("Audio file is empty after verification.", level: .error)
        throw lastError ?? NSError(domain: "TranscriptionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio samples are empty"])
    }

    func clearCache() {
        whisperKit = nil
        currentModelURL = nil
    }
}
