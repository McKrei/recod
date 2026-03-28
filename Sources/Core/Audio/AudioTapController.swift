@preconcurrency import AVFoundation
import Foundation

final class AudioTapController: @unchecked Sendable {
    private let streamBuffer: AudioStreamBuffer
    private let levelMonitor: AudioLevelMonitor
    private let fileFactory: RecordingFileFactory

    private var audioFile: AVAudioFile?
    private var tapInstalled = false
    private var tapBufferCount = 0

    init(
        streamBuffer: AudioStreamBuffer,
        levelMonitor: AudioLevelMonitor,
        fileFactory: RecordingFileFactory
    ) {
        self.streamBuffer = streamBuffer
        self.levelMonitor = levelMonitor
        self.fileFactory = fileFactory
    }

    var currentRecordingURL: URL? { audioFile?.url }
    var bufferCount: Int { tapBufferCount }

    @discardableResult
    func prepareForRecording(on mixer: AVAudioMixerNode) throws -> AVAudioFormat {
        let tapFormat = mixer.outputFormat(forBus: 0)
        Log("Tap format: \(tapFormat.sampleRate)Hz, \(tapFormat.channelCount)ch")

        streamBuffer.prepare(for: tapFormat)
        streamBuffer.clear()

        audioFile = try fileFactory.makeRecordingFile(for: tapFormat)
        if let audioFile {
            Log("Created WAV file: \(tapFormat.sampleRate)Hz \(tapFormat.channelCount)ch — \(audioFile.url.path)")
        }

        removeTap(from: mixer)
        tapBufferCount = 0
        installTap(on: mixer)

        return tapFormat
    }

    func finishRecording(on mixer: AVAudioMixerNode?) -> URL? {
        removeTap(from: mixer)
        let url = audioFile?.url
        audioFile = nil
        tapBufferCount = 0
        return url
    }

    private func installTap(on mixer: AVAudioMixerNode) {
        mixer.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self else { return }

            if self.tapBufferCount == 0 {
                Log("Tap FIRST buffer: \(buffer.frameLength) frames @ \(buffer.format.sampleRate)Hz \(buffer.format.channelCount)ch")
            } else if self.tapBufferCount == 10 {
                Log("Tap alive: 10 buffers received")
            }
            self.tapBufferCount += 1

            do {
                if let audioFile = self.audioFile {
                    try audioFile.write(from: buffer)
                }
            } catch {
                Log("Write error: \(error)", level: .error)
            }

            self.streamBuffer.processBuffer(buffer)
            self.levelMonitor.processBuffer(buffer)
        }
        tapInstalled = true
    }

    private func removeTap(from mixer: AVAudioMixerNode?) {
        guard tapInstalled, let mixer else { return }
        mixer.removeTap(onBus: 0)
        tapInstalled = false
    }
}
