@preconcurrency import AVFoundation
import AppKit
import ScreenCaptureKit
import CoreMedia

public enum AudioRecorderError: Error {
    case permissionDenied
    case setupFailed
    case recordingFailed
}

public class AudioRecorder: NSObject, ObservableObject, @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tapInstalled = false

    // System Audio
    private var scStream: SCStream?
    private var sysAudioSourceNode: AVAudioSourceNode?

    // Config
    public var recordSystemAudio: Bool = false

    @Published public var isRecording = false

    public func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    public func startRecording() async throws {
        let granted = await requestPermission()
        guard granted else { throw AudioRecorderError.permissionDenied }

        let engine = AVAudioEngine()
        let mainMixer = engine.mainMixerNode

        // CRITICAL FIX: Silence the main mixer output to prevent feedback loop.
        // We only want to record, not play back the mic/system audio to speakers.
        mainMixer.outputVolume = 0.0

        // Create a separate mixer for recording
        let recordingMixer = AVAudioMixerNode()
        engine.attach(recordingMixer)

        // Output format (Stereo, 16kHz)
        // We use 2 channels: Left = Mic, Right = System
        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 2, interleaved: false)!

        // System Audio Format (Stereo, 48kHz) - To match SCStream
        let sysFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!

        // 1. Setup Microphone (Left Channel)
        let inputNode = engine.inputNode
        let micFormat = inputNode.outputFormat(forBus: 0)
        let micMixer = AVAudioMixerNode()
        engine.attach(micMixer)

        // Downmix mic to mono first if needed, then pan
        engine.connect(inputNode, to: micMixer, format: micFormat)
        micMixer.pan = -1.0 // Pan hard LEFT

        // Connect micMixer to recordingMixer
        engine.connect(micMixer, to: recordingMixer, format: outputFormat)

        // 2. Setup System Audio (Right Channel)
        var sysPlayerNode: AVAudioPlayerNode?
        if recordSystemAudio {
            if #available(macOS 12.3, *) {
                sysPlayerNode = AVAudioPlayerNode()
                if let sysPlayer = sysPlayerNode {
                    engine.attach(sysPlayer)
                    sysPlayer.pan = 1.0 // Pan hard RIGHT
                    // Connect sysPlayer to recordingMixer
                    engine.connect(sysPlayer, to: recordingMixer, format: sysFormat)
                }

                try await startSystemAudioCapture(to: sysPlayerNode!)
            } else {
                Log("System audio recording requires macOS 12.3+", level: .error)
            }
        }

        // Connect recordingMixer to mainMixer (to keep graph valid), but mainMixer output is silenced.
        engine.connect(recordingMixer, to: mainMixer, format: outputFormat)

        let fileURL = getNewRecordingURL()

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 2, // Stereo
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
            Log("Created 16kHz Stereo WAV file: \(fileURL.path)")
        } catch {
            Log("Failed to create audio file: \(error)", level: .error)
            throw AudioRecorderError.setupFailed
        }

        // Install Tap on RECORDING Mixer to capture combined output
        recordingMixer.installTap(onBus: 0, bufferSize: 4096, format: outputFormat) { [weak self] buffer, time in
            guard let self = self, let audioFile = self.audioFile else { return }

            do {
                try audioFile.write(from: buffer)
            } catch {
                Log("Write error: \(error)", level: .error)
            }
        }

        tapInstalled = true

        do {
            engine.prepare()
            try engine.start()
            sysPlayerNode?.play() // Start playing silence/buffers

            self.audioEngine = engine
            await MainActor.run { self.isRecording = true }
            Log("Recording started (System Audio: \(recordSystemAudio))")
        } catch {
            Log("Engine start failed: \(error)", level: .error)
            throw AudioRecorderError.setupFailed
        }
    }

    public func stopRecording() async -> URL? {
        guard let engine = audioEngine, isRecording else { return nil }

        try? await Task.sleep(nanoseconds: 500_000_000)

        // Stop Screen Capture
        if #available(macOS 12.3, *) {
            if let stream = scStream {
                try? await stream.stopCapture()
                scStream = nil
            }
        }

        // Note: Tap is now on separate mixer, but engine release handles it.
        // Good practice to remove it though.
        // We don't have easy access to recordingMixer variable here unless stored.
        // But throwing away the engine cleans it up.

        engine.stop()
        let url = audioFile?.url
        audioFile = nil

        await MainActor.run { self.isRecording = false }
        self.audioEngine = nil
        Log("Recording stopped and file closed")
        return url
    }

    // MARK: - System Audio Capture (macOS 12.3+)

    @available(macOS 12.3, *)
    private func startSystemAudioCapture(to playerNode: AVAudioPlayerNode) async throws {
        // Fallback to .current for compatibility
        let content = try await SCShareableContent.current

        guard let display = content.displays.first else { throw AudioRecorderError.setupFailed }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 5
        config.sampleRate = 48000
        config.channelCount = 2

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)

        let output = StreamOutput(playerNode: playerNode)

        try stream.addStreamOutput(output, type: SCStreamOutputType.audio, sampleHandlerQueue: DispatchQueue(label: "audio.capture.queue"))

        try await stream.startCapture()
        self.scStream = stream

        objc_setAssociatedObject(self, "StreamOutput", output, .OBJC_ASSOCIATION_RETAIN)
    }

    private func getNewRecordingURL() -> URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let recordingsDir = appSupportURL.appendingPathComponent("Recod/Recordings")
        try? fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return recordingsDir.appendingPathComponent("recording-\(formatter.string(from: Date())).wav")
    }

    @MainActor
    public func revealRecordingsInFinder() {
        let fileManager = FileManager.default
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
             let recordingsDir = appSupportURL.appendingPathComponent("Recod/Recordings")
             NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: recordingsDir.path)
        }
    }
}

// MARK: - SCStreamOutput Helper

@available(macOS 12.3, *)
private class StreamOutput: NSObject, SCStreamOutput {
    let playerNode: AVAudioPlayerNode
    let engineSampleRate: Double = 16000.0
    var converter: AVAudioConverter?

    init(playerNode: AVAudioPlayerNode) {
        self.playerNode = playerNode
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == SCStreamOutputType.audio else { return }

        if let buffer = createPCMBuffer(from: sampleBuffer) {
            playerNode.scheduleBuffer(buffer)
        }
    }

    func createPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        try? sampleBuffer.withAudioBufferList { audioBufferList, _ -> AVAudioPCMBuffer? in
            guard var absd = sampleBuffer.formatDescription?.audioStreamBasicDescription else { return nil }
            guard let format = withUnsafePointer(to: &absd, { AVAudioFormat(streamDescription: $0) }) else { return nil }

            let frameCount = UInt32(sampleBuffer.numSamples)
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
            pcmBuffer.frameLength = frameCount

            if let floatChannelData = pcmBuffer.floatChannelData {
                for (i, buffer) in audioBufferList.enumerated() {
                    if i < Int(format.channelCount) {
                         if let srcData = buffer.mData {
                             let dst = floatChannelData[i]
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
