// Sources/Core/Services/ParakeetTranscriptionService.swift

import Foundation
@preconcurrency import AVFoundation
import SherpaOnnxSwift

// MARK: - Errors

enum ParakeetTranscriptionError: LocalizedError {
    case recognizerNotInitialized
    case modelDirectoryMissing(String)
    case audioFileReadFailed(String)
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .recognizerNotInitialized:
            return "Parakeet recognizer is not initialized. Call prepareModel() first."
        case .modelDirectoryMissing(let path):
            return "Parakeet model directory not found: \(path)"
        case .audioFileReadFailed(let reason):
            return "Failed to read audio file: \(reason)"
        case .conversionFailed:
            return "Failed to convert audio to 16kHz mono."
        }
    }
}

// MARK: - Service

actor ParakeetTranscriptionService {
    static let shared = ParakeetTranscriptionService()

    private let longAudioChunkSeconds: Double = 30.0
    private let longAudioChunkThresholdSeconds: Double = 120.0

    private var recognizer: SherpaOnnxOfflineRecognizer?
    private var currentModelDir: URL?

    init() {}

    // MARK: - Model Loading

    /// Pre-loads the Parakeet model from the given directory.
    /// The directory must contain: encoder.int8.onnx, decoder.int8.onnx, joiner.int8.onnx, tokens.txt
    func prepareModel(modelDir: URL, hotwords: [ParakeetHotword] = []) async {
        if currentModelDir == modelDir && recognizer != nil {
            return
        }

        await FileLogger.shared.log("Pre-loading Parakeet model: \(modelDir.lastPathComponent)")
        let start = Date()

        let encoderPath = modelDir.appendingPathComponent("encoder.int8.onnx").path
        let decoderPath = modelDir.appendingPathComponent("decoder.int8.onnx").path
        let joinerPath = modelDir.appendingPathComponent("joiner.int8.onnx").path
        let tokensPath = modelDir.appendingPathComponent("tokens.txt").path

        // Verify files exist
        let fm = FileManager.default
        for path in [encoderPath, decoderPath, joinerPath, tokensPath] {
            guard fm.fileExists(atPath: path) else {
                await FileLogger.shared.log("Parakeet model file missing: \(path)", level: .error)
                recognizer = nil
                currentModelDir = nil
                return
            }
        }

        // Build config
        let transducerConfig = sherpaOnnxOfflineTransducerModelConfig(
            encoder: encoderPath,
            decoder: decoderPath,
            joiner: joinerPath
        )

        let modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: tokensPath,
            transducer: transducerConfig,
            numThreads: max(ProcessInfo.processInfo.activeProcessorCount / 2, 2),
            provider: "cpu",
            debug: 0,
            modelType: "nemo_transducer"
        )

        let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80)

        // Compile hotwords file if rules exist
        var hotwordsPath = ""
        var avgScore: Float = 1.5
        var useHotwords = false
        
        if let result = DictionaryBiasingCompiler.compileParakeetHotwordsFile(from: hotwords) {
            hotwordsPath = result.path
            avgScore = result.avgScore
            useHotwords = true
            await FileLogger.shared.log("Compiled hotwords into \(hotwordsPath) (avg weight: \(avgScore))")
        }

        let decodingMethod = useHotwords ? "modified_beam_search" : "greedy_search"
        
        var config = sherpaOnnxOfflineRecognizerConfig(
            featConfig: featConfig,
            modelConfig: modelConfig,
            decodingMethod: decodingMethod,
            hotwordsFile: hotwordsPath,
            hotwordsScore: avgScore
        )

        recognizer = SherpaOnnxOfflineRecognizer(config: &config)
        currentModelDir = modelDir

        let duration = Date().timeIntervalSince(start)
        await FileLogger.shared.log(String(format: "Parakeet model loaded: %.2fs", duration))
    }

    // MARK: - Batch Transcription (from audio samples)

    /// Transcribes raw audio samples (16kHz mono Float32).
    /// Can be called from streaming service for individual VAD segments.
    ///
    /// - Parameters:
    ///   - audioSamples: Audio samples normalized to [-1, 1] at 16kHz mono.
    ///   - timeOffset: Offset to add to all timestamps (for streaming chunks).
    /// - Returns: Tuple of (cleaned text, timestamped segments).
    func transcribe(audioSamples: [Float], timeOffset: TimeInterval = 0) -> (String, [TranscriptionSegment]) {
        guard let recognizer = recognizer else {
            return ("", [])
        }

        guard !audioSamples.isEmpty else {
            return ("", [])
        }

        let result = recognizer.decode(samples: audioSamples, sampleRate: 16_000)
        let text = result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        guard !text.isEmpty else {
            return ("", [])
        }

        // Build timestamped segments from BPE tokens
        let tokens = result.tokens
        let timestamps = result.timestamps
        let durations = result.durations

        let segments: [TranscriptionSegment]
        if !tokens.isEmpty && !timestamps.isEmpty {
            segments = ParakeetSegmentBuilder.buildSegments(
                tokens: tokens,
                timestamps: timestamps,
                durations: durations,
                timeOffset: timeOffset
            )
        } else {
            // Fallback: single segment covering entire audio
            let audioDuration = TimeInterval(audioSamples.count) / 16000.0
            segments = [
                TranscriptionSegment(
                    start: timeOffset,
                    end: timeOffset + audioDuration,
                    text: text
                )
            ]
        }

        return (text, segments)
    }

    // MARK: - Batch Transcription (from WAV file)

    /// Transcribes a WAV audio file. Handles resampling to 16kHz mono internally.
    /// Matches `TranscriptionService.transcribe(audioURL:modelURL:)` return signature.
    ///
    /// - Parameters:
    ///   - audioURL: URL to the local audio file.
    ///   - modelDir: URL to the Parakeet model directory.
    /// - Returns: Tuple of (cleaned text, timestamped segments).
    func transcribe(audioURL: URL, modelDir: URL, hotwords: [ParakeetHotword] = []) async throws -> (String, [TranscriptionSegment]) {
        let startTime = Date()
        await FileLogger.shared.log("--- Parakeet Transcription Start ---")

        // Ensure model is loaded with hotwords
        if recognizer == nil || currentModelDir != modelDir || !hotwords.isEmpty {
            await prepareModel(modelDir: modelDir, hotwords: hotwords)
        }

        guard recognizer != nil else {
            throw ParakeetTranscriptionError.recognizerNotInitialized
        }

        // Wait for audio file to be ready
        let readiness = await AudioFileReadinessChecker.waitForReadableFrames(at: audioURL)
        if readiness.frameCount == 0 {
            await FileLogger.shared.log("Skipping transcription for empty audio file.")
            return ("", [])
        }
        await FileLogger.shared.log("Audio file verified and ready (\(readiness.frameCount) frames)")

        // Load and convert audio on a background thread
        await FileLogger.shared.log("Loading and converting audio to 16kHz mono...")
        let samples = try await AudioUtilities.load16kHzMonoFloatSamples(from: audioURL)
        await FileLogger.shared.log("Audio loaded: \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / 16000.0))s)")

        // Run inference (chunked for long audio to avoid memory spikes/freezes)
        await FileLogger.shared.log("Starting Parakeet inference...")
        let inferStart = Date()

        let audioSeconds = Double(samples.count) / 16000.0
        let text: String
        let segments: [TranscriptionSegment]

        if audioSeconds >= longAudioChunkThresholdSeconds {
            await FileLogger.shared.log(
                String(format: "Using chunked Parakeet inference: %.1fs audio, chunk=%.0fs", audioSeconds, longAudioChunkSeconds),
                level: .info
            )
            (text, segments) = transcribeLongAudioInChunks(samples: samples, chunkSeconds: longAudioChunkSeconds)
        } else {
            (text, segments) = transcribe(audioSamples: samples)
        }

        let inferDuration = Date().timeIntervalSince(inferStart)
        let totalDuration = Date().timeIntervalSince(startTime)

        await FileLogger.shared.log(String(format: "Inference completed: %.2fs", inferDuration))
        await FileLogger.shared.log("Result: \(segments.count) segments, \(text.count) chars")
        await FileLogger.shared.log(String(format: "Total process time: %.2fs", totalDuration))
        await FileLogger.shared.log("--- Parakeet Transcription End ---")

        return (text, segments)
    }

    // MARK: - Long Audio Transcription

    private func transcribeLongAudioInChunks(samples: [Float], chunkSeconds: Double) -> (String, [TranscriptionSegment]) {
        guard !samples.isEmpty else { return ("", []) }

        let chunkSize = max(Int(chunkSeconds * 16000.0), 16000)
        var index = 0

        var allTextParts: [String] = []
        var allSegments: [TranscriptionSegment] = []

        while index < samples.count {
            let end = min(index + chunkSize, samples.count)
            let chunk = Array(samples[index..<end])
            let offset = Double(index) / 16000.0

            autoreleasepool {
                let (chunkText, chunkSegments) = transcribe(audioSamples: chunk, timeOffset: offset)
                if !chunkText.isEmpty {
                    allTextParts.append(chunkText)
                }
                if !chunkSegments.isEmpty {
                    allSegments.append(contentsOf: chunkSegments)
                }
            }

            index = end
        }

        return (allTextParts.joined(separator: " "), allSegments)
    }

    // MARK: - Cache Management

    func clearCache() {
        recognizer = nil
        currentModelDir = nil
    }

    var isModelLoaded: Bool {
        recognizer != nil
    }
}
