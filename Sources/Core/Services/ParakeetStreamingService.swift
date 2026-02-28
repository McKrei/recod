// Sources/Core/Services/ParakeetStreamingService.swift

import Foundation
import SwiftData
import SherpaOnnxSwift

@MainActor
final class ParakeetStreamingService: ObservableObject {
    static let shared = ParakeetStreamingService()

    private var isStreaming = false
    private var streamingTask: Task<Void, Never>?

    private var vad: SherpaOnnxVoiceActivityDetectorWrapper?
    private var lastProcessedSampleCount = 0
    private var accumulatedSegments: [TranscriptionSegment] = []
    private var accumulatedText: String = ""

    private init() {}

    // MARK: - Start Streaming

    func startStreaming(
        recording: Recording,
        audioRecorder: AudioRecorder,
        modelContext: ModelContext,
        modelDir: URL,
        vadModelPath: URL
    ) {
        guard !isStreaming else { return }
        isStreaming = true
        lastProcessedSampleCount = 0
        accumulatedSegments = []
        accumulatedText = ""

        // 1. Initialize VAD
        setupVAD(vadModelPath: vadModelPath)

        // 2. Ensure ParakeetTranscriptionService has model loaded
        Task {
            await ParakeetTranscriptionService.shared.prepareModel(modelDir: modelDir)
        }

        // 3. Start polling loop
        streamingTask = Task { [weak self] in
            guard let self else { return }

            while self.isStreaming {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms poll interval
                guard self.isStreaming else { break }

                // Fetch only the new samples from the buffer to prevent O(N^2) memory copying
                // which causes the tap block to drop and audio duration to be 0 seconds.
                let bufferTotalCount = audioRecorder.getAudioSamples().count
                guard bufferTotalCount > self.lastProcessedSampleCount else { continue }
                
                let newSamples = audioRecorder.getNewAudioSamples(from: self.lastProcessedSampleCount)
                self.lastProcessedSampleCount += newSamples.count

                // Feed to VAD in windowSize chunks (512 samples = 32ms at 16kHz)
                self.feedVAD(samples: newSamples)

                // Process all completed speech segments from VAD
                var didUpdate = false
                while self.vad?.isEmpty() == false {
                    guard let segment = self.vad?.front() else { break }
                    let speechSamples = segment.samples
                    let segmentStartSample = segment.start // sample index in the full stream
                    self.vad?.pop()

                    guard !speechSamples.isEmpty else { continue }

                    // Time offset: VAD segment.start is the sample index from stream start
                    let timeOffset = TimeInterval(segmentStartSample) / 16000.0

                    // Transcribe this speech segment
                    let (text, segments) = ParakeetTranscriptionService.shared
                        .transcribe(audioSamples: speechSamples, timeOffset: timeOffset)

                    guard !text.isEmpty else { continue }

                    // Accumulate results
                    self.accumulatedSegments.append(contentsOf: segments)
                    if self.accumulatedText.isEmpty {
                        self.accumulatedText = text
                    } else {
                        self.accumulatedText += " " + text
                    }

                    didUpdate = true
                }

                // Update Recording model if we got new transcriptions
                if didUpdate {
                    recording.liveTranscription = self.accumulatedText
                    recording.segments = self.accumulatedSegments
                    try? modelContext.save()
                }
            }
        }
    }

    // MARK: - Stop Streaming

    func stopStreaming() {
        isStreaming = false
        streamingTask?.cancel()
        streamingTask = nil

        // Flush any remaining speech that VAD hasn't finalized
        // (e.g., user stopped recording mid-sentence)
        vad?.flush()
        vad = nil
    }

    /// Flushes VAD and returns any final segments that were in-flight.
    /// Call this right before stopStreaming to capture trailing speech.
    func flushAndCollectRemaining() -> (String, [TranscriptionSegment]) {
        guard let vad = vad else { return ("", []) }

        // Flush forces VAD to emit any partial speech segment
        vad.flush()

        var finalText = ""
        var finalSegments: [TranscriptionSegment] = []

        while !vad.isEmpty() {
            let segment = vad.front()
            let speechSamples = segment.samples
            let segmentStartSample = segment.start
            vad.pop()

            guard !speechSamples.isEmpty else { continue }

            let timeOffset = TimeInterval(segmentStartSample) / 16000.0
            let (text, segments) = ParakeetTranscriptionService.shared
                .transcribe(audioSamples: speechSamples, timeOffset: timeOffset)

            guard !text.isEmpty else { continue }

            finalSegments.append(contentsOf: segments)
            if finalText.isEmpty {
                finalText = text
            } else {
                finalText += " " + text
            }
        }

        // Merge with accumulated
        if !finalText.isEmpty {
            accumulatedSegments.append(contentsOf: finalSegments)
            if accumulatedText.isEmpty {
                accumulatedText = finalText
            } else {
                accumulatedText += " " + finalText
            }
        }

        return (accumulatedText, accumulatedSegments)
    }

    // MARK: - VAD Setup

    private func setupVAD(vadModelPath: URL) {
        let sileroConfig = sherpaOnnxSileroVadModelConfig(
            model: vadModelPath.path,
            threshold: 0.5,
            minSilenceDuration: 0.5,   // 500ms silence → end of speech
            minSpeechDuration: 0.25,   // Ignore speech shorter than 250ms
            windowSize: 512,           // 32ms at 16kHz
            maxSpeechDuration: 30.0    // Force-split after 30s (safety)
        )

        var vadConfig = sherpaOnnxVadModelConfig(
            sileroVad: sileroConfig,
            sampleRate: 16000,
            numThreads: 1,
            provider: "cpu",
            debug: 0
        )

        // buffer_size_in_seconds: how much audio the circular buffer can hold
        self.vad = SherpaOnnxVoiceActivityDetectorWrapper(
            config: &vadConfig,
            buffer_size_in_seconds: 120.0  // Up to 2 minutes of recording
        )
    }

    // MARK: - VAD Feeding

    private func feedVAD(samples: [Float]) {
        guard let vad = vad else { return }

        // Feed samples to VAD in windowSize chunks (512 samples)
        // VAD requires exact windowSize input per call
        let windowSize = 512
        var offset = 0
        while offset + windowSize <= samples.count {
            let chunk = Array(samples[offset..<offset + windowSize])
            vad.acceptWaveform(samples: chunk)
            offset += windowSize
        }
        // Remaining samples (< windowSize) are discarded.
        // At 16kHz/512, that's at most 31ms of audio — negligible.
    }
}
