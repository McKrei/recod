import AVFoundation
import ScreenCaptureKit
import CoreMedia

/// A helper class acting as the output delegate for SCStream.
/// It receives CMSampleBuffers from ScreenCaptureKit, converts them to AVAudioPCMBuffer,
/// and schedules them on the provided AVAudioPlayerNode for mixing.
@available(macOS 12.3, *)
class StreamOutput: NSObject, SCStreamOutput {
    private let playerNode: AVAudioPlayerNode

    // We assume the engine runs at 16k, but ScreenCaptureKit usually gives 48k or 44.1k.
    // The playerNode handles playback into the mixer, which handles sample rate conversion.

    init(playerNode: AVAudioPlayerNode) {
        self.playerNode = playerNode
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // We only care about audio samples here
        guard type == SCStreamOutputType.audio else { return }

        if let buffer = createPCMBuffer(from: sampleBuffer) {
            playerNode.scheduleBuffer(buffer)
        }
    }

    /// Converts a CMSampleBuffer (containing audio) to an AVAudioPCMBuffer.
    /// - Parameter sampleBuffer: The input CMSampleBuffer from SCStream.
    /// - Returns: An AVAudioPCMBuffer ready for playback, or nil if conversion fails.
    private func createPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        // Use withAudioBufferList to safely access the underlying AudioBufferList
        try? sampleBuffer.withAudioBufferList { audioBufferList, _ -> AVAudioPCMBuffer? in
            // 1. Get the AudioStreamBasicDescription (ASBD) from the sample buffer
            guard var absd = sampleBuffer.formatDescription?.audioStreamBasicDescription else { return nil }

            // 2. Create an AVAudioFormat from the ASBD.
            // We use withUnsafePointer to properly pass the C-struct pointer.
            guard let format = withUnsafePointer(to: &absd, { AVAudioFormat(streamDescription: $0) }) else { return nil }

            // 3. Create the AVAudioPCMBuffer
            let frameCount = UInt32(sampleBuffer.numSamples)
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
            pcmBuffer.frameLength = frameCount

            // 4. Copy the audio data
            // We iterate over the buffers in the AudioBufferList and copy memory to the AVAudioPCMBuffer's floatChannelData.
            if let floatChannelData = pcmBuffer.floatChannelData {
                for (i, buffer) in audioBufferList.enumerated() {
                    // Ensure we don't go out of bounds of the format's channel count
                    if i < Int(format.channelCount) {
                         if let srcData = buffer.mData {
                             let dst = floatChannelData[i]
                             // Calculate safe byte size to copy
                             let bytesToCopy = min(Int(buffer.mDataByteSize), Int(frameCount) * MemoryLayout<Float>.size)
                             memcpy(dst, srcData, bytesToCopy)
                         }
                    }
                }
            }

            return pcmBuffer
        }
    }
}
