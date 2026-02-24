import Foundation
import SwiftData
@preconcurrency import WhisperKit

@MainActor
final class StreamingTranscriptionService: ObservableObject {
    static let shared = StreamingTranscriptionService()

    private var isStreaming = false
    private var streamTask: Task<Void, Error>?

    private init() {}

    func startStreaming(
        recording: Recording,
        audioRecorder: AudioRecorder,
        modelContext: ModelContext,
        modelURL: URL
    ) {
        guard !isStreaming else { return }
        isStreaming = true

        streamTask = Task {
            var lastConfirmedEndSeconds: Float = 0
            var confirmedSegments: [TranscriptionSegment] = []
            var detectedLanguage: String? = nil

            // Wait for model cache in TranscriptionService if not loaded
            await TranscriptionService.shared.prepareModel(modelURL: modelURL)
            guard let whisperKit = TranscriptionService.shared.activeWhisperKit else {
                return
            }

            while isStreaming {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds interval
                guard isStreaming else { break }

                let samples = audioRecorder.getAudioSamples()
                let sampleRate: Float = 16000.0
                let totalSeconds = Float(samples.count) / sampleRate

                // Only transcribe if we have at least 3 seconds of new audio
                if totalSeconds - lastConfirmedEndSeconds < 3.0 {
                    continue
                }

                if detectedLanguage == nil {
                    do {
                        let detectionResult = try await whisperKit.detectLangauge(audioArray: samples)
                        detectedLanguage = detectionResult.language
                    } catch {
                        // ignore and let it default
                    }
                }

                var options = DecodingOptions()
                options.task = .transcribe
                options.language = detectedLanguage
                options.clipTimestamps = [lastConfirmedEndSeconds]
                options.temperature = 0.0
                options.chunkingStrategy = .vad

                do {
                    let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
                    guard isStreaming else { break } // Check again after await

                    let allSegments = results.flatMap { $0.segments }

                    let requiredConfirmationCount = 2
                    if allSegments.count > requiredConfirmationCount {
                        let toConfirm = allSegments.prefix(allSegments.count - requiredConfirmationCount)
                        let remaining = allSegments.suffix(requiredConfirmationCount)

                        if let lastConfirmed = toConfirm.last {
                            lastConfirmedEndSeconds = lastConfirmed.end
                            let newConfirmed = toConfirm.map {
                                TranscriptionSegment(start: Double($0.start), end: Double($0.end), text: self.cleanTranscriptionText($0.text))
                            }
                            confirmedSegments.append(contentsOf: newConfirmed)
                        }

                        let remainingText = remaining.map { self.cleanTranscriptionText($0.text) }.joined(separator: " ")
                        let confirmedText = confirmedSegments.map { $0.text }.joined(separator: " ")

                        recording.liveTranscription = [confirmedText, remainingText].filter { !$0.isEmpty }.joined(separator: " ")

                        let remainingSegments = remaining.map {
                            TranscriptionSegment(start: Double($0.start), end: Double($0.end), text: self.cleanTranscriptionText($0.text))
                        }
                        recording.segments = confirmedSegments + remainingSegments

                    } else {
                        // Not enough to confirm, just show as live
                        let allText = allSegments.map { self.cleanTranscriptionText($0.text) }.joined(separator: " ")
                        let confirmedText = confirmedSegments.map { $0.text }.joined(separator: " ")

                        recording.liveTranscription = [confirmedText, allText].filter { !$0.isEmpty }.joined(separator: " ")

                        let newSegments = allSegments.map {
                            TranscriptionSegment(start: Double($0.start), end: Double($0.end), text: self.cleanTranscriptionText($0.text))
                        }
                        recording.segments = confirmedSegments + newSegments
                    }

                    try? modelContext.save()

                } catch {
                    // Ignore errors during stream pass, might succeed in next chunk
                }
            }
        }
    }

    func stopStreaming() {
        isStreaming = false
        streamTask?.cancel()
        streamTask = nil
    }

    private func cleanTranscriptionText(_ text: String) -> String {
        let pattern = "<\\|.*?\\|>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let cleaned = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
