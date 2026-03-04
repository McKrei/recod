import Foundation
@preconcurrency import AVFoundation

/// Manages thread-safe accumulation of 16kHz audio samples for streaming transcription.
/// Converts native hardware PCM buffers into 16kHz float arrays.
public final class AudioStreamBuffer: @unchecked Sendable {
    private var buffer: [Float] = []
    private let queue = DispatchQueue(label: "com.recod.audioStreamBufferQueue")

    private var audioConverter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    public init() {}

    /// Prepares the internal converter for the incoming format.
    /// Sets up the target format as 16kHz mono float, which is required by transcription models.
    public func prepare(for inputFormat: AVAudioFormat) {
        let format16kHz = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)
        guard let target = format16kHz else {
            Log("AudioStreamBuffer: Failed to create 16kHz format", level: .error)
            return
        }
        self.targetFormat = target

        audioConverter = AVAudioConverter(from: inputFormat, to: target)
        if audioConverter == nil {
            Log("AudioStreamBuffer: Failed to create AVAudioConverter from \(inputFormat.sampleRate)Hz to 16kHz", level: .error)
        }
    }

    /// Converts the incoming buffer to 16kHz and appends it to the internal array.
    public func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter = audioConverter, let format16kHz = targetFormat else { return }

        // Calculate max capacity for converted buffer
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * (format16kHz.sampleRate / buffer.format.sampleRate)) + 4096
        guard capacity > 0, let outputBuffer = AVAudioPCMBuffer(pcmFormat: format16kHz, frameCapacity: capacity) else { return }

        var error: NSError? = nil
        final class ProviderState: @unchecked Sendable {
            var hasProvidedData = false
        }
        let state = ProviderState()

        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            if state.hasProvidedData {
                outStatus.pointee = .noDataNow
                return nil
            }
            state.hasProvidedData = true
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if error == nil, let channelData = outputBuffer.floatChannelData {
            let frameLength = Int(outputBuffer.frameLength)
            if frameLength > 0 {
                let bufferPointer = UnsafeBufferPointer<Float>(start: channelData[0], count: frameLength)
                let samples = Array(bufferPointer)

                queue.async {
                    self.buffer.append(contentsOf: samples)
                }
            }
        } else if let error = error {
            Log("AudioStreamBuffer: conversion error: \(error.localizedDescription)", level: .error)
        }
    }

    /// Returns a full copy of the accumulated 16kHz audio samples.
    public func getSamples() -> [Float] {
        queue.sync { buffer }
    }

    /// Returns the current number of accumulated samples without copying.
    public func getSampleCount() -> Int {
        queue.sync { buffer.count }
    }

    /// Returns the accumulated audio samples added after the specified index.
    /// Useful for streaming transcription to avoid copying the entire buffer repeatedly.
    public func getNewSamples(from index: Int) -> [Float] {
        queue.sync {
            guard index < buffer.count else { return [] }
            return Array(buffer[index...])
        }
    }

    /// Clears the accumulated samples and resets the converter state.
    public func clear() {
        queue.sync {
            buffer.removeAll(keepingCapacity: true)
        }
        audioConverter?.reset()
    }
}
