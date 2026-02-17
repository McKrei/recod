@preconcurrency import AVFoundation
import AppKit
import ScreenCaptureKit
import CoreMedia

public enum AudioRecorderError: Error {
    case permissionDenied
    case setupFailed
    case recordingFailed
}

/// Manages audio recording from both the microphone and system audio (macOS 12.3+).
///
/// This class configures an `AVAudioEngine` to mix input from the default microphone
/// and the system audio capture stream (via `ScreenCaptureKit`).
public class AudioRecorder: NSObject, ObservableObject, @unchecked Sendable {
    // MARK: - Properties

    private let engine = AVAudioEngine()
    private let recordingMixer = AVAudioMixerNode()
    private let micMixer = AVAudioMixerNode()
    private var sysPlayerNode: AVAudioPlayerNode?

    private var audioFile: AVAudioFile?
    private var tapInstalled = false
    private var graphInitialized = false

    // System Audio
    private var scStream: SCStream?

    // Config
    public var recordSystemAudio: Bool = false

    @Published public var isRecording = false

    // MARK: - Initializer & Pre-warm

    public override init() {
        super.init()
    }

    /// Pre-warms the audio engine by initializing the graph and starting the engine.
    /// This triggers hardware initialization and permission prompts.
    public func prewarm() {
        setupGraph()
        Task {
            do {
                engine.prepare()
                try engine.start()
                Log("AudioRecorder engine pre-warmed for 1s...")
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                engine.stop()
                Log("AudioRecorder engine stopped after pre-warm (indicator off)")
            } catch {
                Log("AudioRecorder pre-warm engine start failed: \(error)", level: .error)
            }
        }
    }

    // MARK: - Public Methods

    public func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Starts the recording process.
    public func startRecording() async throws {
        let granted = await requestPermission()
        guard granted else { throw AudioRecorderError.permissionDenied }

        setupGraph()

        // 1. Ensure engine is running
        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
                // Give some time for hardware to stabilize
                try? await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                Log("Engine start failed: \(error)", level: .error)
                throw AudioRecorderError.setupFailed
            }
        }

        // 2. Setup System Audio Capture if needed
        if recordSystemAudio {
            if #available(macOS 12.3, *) {
                if scStream == nil {
                    try await startSystemAudioCapture()
                }
            }
        }

        sysPlayerNode?.play()

        // 3. Create File
        let fileURL = getNewRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 2,
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

        // 4. Install Tap
        let outputFormat = recordingMixer.outputFormat(forBus: 0)
        recordingMixer.installTap(onBus: 0, bufferSize: 4096, format: outputFormat) { [weak self] buffer, time in
            guard let self = self, let audioFile = self.audioFile else { return }
            do {
                try audioFile.write(from: buffer)
            } catch {
                Log("Write error: \(error)", level: .error)
            }
        }
        tapInstalled = true

        await MainActor.run { self.isRecording = true }
        Log("Recording started (System Audio: \(recordSystemAudio))")
    }

    /// Stops the recording and closes the file.
    public func stopRecording() async -> URL? {
        guard isRecording else { return nil }

        // Grace period to catch last samples
        try? await Task.sleep(nanoseconds: 300_000_000)

        recordingMixer.removeTap(onBus: 0)
        tapInstalled = false

        // Stop Screen Capture
        if #available(macOS 12.3, *) {
            if let stream = scStream {
                try? await stream.stopCapture()
                scStream = nil
            }
        }

        sysPlayerNode?.stop()

        let url = audioFile?.url
        audioFile = nil

        await MainActor.run { self.isRecording = false }
        Log("Recording stopped")

        // Stop engine to hide the orange dot and save resources
        engine.stop()

        return url
    }

    // MARK: - Private Helpers

    private func setupGraph() {
        guard !graphInitialized else { return }

        Log("Initializing AudioRecorder graph...")

        let mainMixer = engine.mainMixerNode
        mainMixer.outputVolume = 0.0

        engine.attach(recordingMixer)
        engine.attach(micMixer)

        // Formats
        let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 2, interleaved: false)!
        let sysFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!

        // 1. Microphone Setup
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        engine.connect(inputNode, to: micMixer, format: inputFormat)
        micMixer.pan = -1.0 // Left
        engine.connect(micMixer, to: recordingMixer, format: recordingFormat)

        // 2. System Audio Setup
        if #available(macOS 12.3, *) {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            player.pan = 1.0 // Right
            engine.connect(player, to: recordingMixer, format: sysFormat)
            self.sysPlayerNode = player
        }

        // 3. Final Connection
        engine.connect(recordingMixer, to: mainMixer, format: recordingFormat)

        graphInitialized = true
        Log("AudioRecorder graph initialized")
    }

    @available(macOS 12.3, *)
    private func startSystemAudioCapture() async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else { throw AudioRecorderError.setupFailed }
        guard let playerNode = sysPlayerNode else { return }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let output = StreamOutput(playerNode: playerNode)

        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: DispatchQueue(label: "audio.capture.queue"))
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
