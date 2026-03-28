@preconcurrency import AVFoundation
import CoreMedia
import ScreenCaptureKit

final class SystemAudioCaptureService: @unchecked Sendable {
    private var stream: SCStream?
    private var streamOutput: StreamOutput?

    @available(macOS 12.3, *)
    func startCapture(with playerNode: AVAudioPlayerNode) async throws {
        guard stream == nil else { return }

        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw AudioRecorderError.setupFailed
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.sampleRate = 48000
        configuration.channelCount = 2

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        let output = StreamOutput(playerNode: playerNode)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: DispatchQueue(label: "audio.capture.queue"))
        try await stream.startCapture()

        self.stream = stream
        self.streamOutput = output
    }

    @available(macOS 12.3, *)
    func stopCapture() async {
        if let stream {
            try? await stream.stopCapture()
        }

        stream = nil
        streamOutput = nil
    }
}
