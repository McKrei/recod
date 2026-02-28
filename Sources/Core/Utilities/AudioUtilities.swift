// Sources/Core/Utilities/AudioUtilities.swift

import Foundation
@preconcurrency import AVFoundation

enum AudioUtilitiesError: LocalizedError {
    case fileReadFailed(String)
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .fileReadFailed(let reason): return "Failed to read audio file: \(reason)"
        case .conversionFailed: return "Failed to convert audio."
        }
    }
}

/// Provides shared audio conversion and manipulation utilities.
struct AudioUtilities {
    
    /// Reads an audio file and converts it to 16kHz mono Float32 samples.
    /// Runs the heavy I/O + conversion on a background thread.
    /// Useful for preparing audio buffers for ML models (e.g., ONNX, CoreML).
    ///
    /// - Parameter url: The URL of the local audio file.
    /// - Returns: An array of audio samples normalized to [-1.0, 1.0].
    static func load16kHzMonoFloatSamples(from url: URL) async throws -> [Float] {
        try await Task.detached {
            let audioFile: AVAudioFile
            do {
                audioFile = try AVAudioFile(forReading: url)
            } catch {
                throw AudioUtilitiesError.fileReadFailed(error.localizedDescription)
            }

            let sourceFormat = audioFile.processingFormat
            let sourceFrameCount = AVAudioFrameCount(audioFile.length)

            guard sourceFrameCount > 0 else {
                throw AudioUtilitiesError.fileReadFailed("Audio file is empty")
            }

            // Target format: 16kHz, mono, Float32
            guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            ) else {
                throw AudioUtilitiesError.conversionFailed
            }

            // If source is already 16kHz mono, read directly
            if sourceFormat.sampleRate == 16000 && sourceFormat.channelCount == 1 {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: sourceFrameCount) else {
                    throw AudioUtilitiesError.conversionFailed
                }
                try audioFile.read(into: buffer)

                guard let channelData = buffer.floatChannelData else {
                    throw AudioUtilitiesError.conversionFailed
                }
                return Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
            }

            // Need conversion — read source into buffer first
            guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: sourceFrameCount) else {
                throw AudioUtilitiesError.conversionFailed
            }
            try audioFile.read(into: sourceBuffer)

            // Create converter
            guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                throw AudioUtilitiesError.conversionFailed
            }

            // Calculate output capacity
            let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(sourceFrameCount) * ratio) + 4096

            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
                throw AudioUtilitiesError.conversionFailed
            }

            // Convert with input block
            final class ProviderState: @unchecked Sendable {
                var hasProvidedData = false
            }
            let state = ProviderState()

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                if state.hasProvidedData {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                state.hasProvidedData = true
                outStatus.pointee = .haveData
                return sourceBuffer
            }

            converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

            if let error = error {
                throw AudioUtilitiesError.fileReadFailed("Audio conversion failed: \(error.localizedDescription)")
            }

            guard let channelData = outputBuffer.floatChannelData else {
                throw AudioUtilitiesError.conversionFailed
            }

            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))

            guard !samples.isEmpty else {
                throw AudioUtilitiesError.fileReadFailed("Conversion produced empty output")
            }

            return samples
        }.value
    }
}
