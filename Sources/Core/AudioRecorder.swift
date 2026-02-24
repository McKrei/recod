@preconcurrency import AVFoundation
import AppKit
import ScreenCaptureKit
import CoreMedia

public enum AudioRecorderError: Error, LocalizedError {
    case permissionDenied
    case setupFailed
    case recordingFailed
    case screenCapturePermissionDenied

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Microphone permission denied"
        case .setupFailed: return "Audio setup failed"
        case .recordingFailed: return "Recording failed"
        case .screenCapturePermissionDenied: return "Screen recording permission is required for system audio capture. Please enable it in System Settings → Privacy & Security → Screen & System Audio Recording."
        }
    }
}

/// Manages audio recording from both the microphone and system audio (macOS 12.3+).
///
/// **Key design decision:** The tap format MUST match the hardware input sample rate.
/// macOS's AVAudioEngine strictly enforces `format.sampleRate == inputHWFormat.sampleRate`
/// in `installTapOnNode`. Therefore we record in the native hardware format (typically 48kHz)
/// and let WhisperKit handle any necessary sample rate conversion during transcription.
public class AudioRecorder: NSObject, ObservableObject, @unchecked Sendable {
    // MARK: - Properties

    private let engine = AVAudioEngine()
    private var recordingMixer: AVAudioMixerNode?
    private var micMixer: AVAudioMixerNode?
    private var sysPlayerNode: AVAudioPlayerNode?

    private var audioFile: AVAudioFile?
    private var tapInstalled = false
    private var graphInitialized = false
    private var graphIncludesSystemAudio = false

    // System Audio
    private var scStream: SCStream?

    // Config
    public var recordSystemAudio: Bool = false

    @Published public var isRecording = false

    // MARK: - Initializer & Pre-warm

    public override init() {
        super.init()
    }

    /// Pre-warms the audio engine to trigger hardware init and permission prompts.
    public func prewarm() {
        // Force mic-only graph for pre-warm
        let savedSysAudio = recordSystemAudio
        recordSystemAudio = false

        setupGraph()
        Task {
            do {
                engine.prepare()
                try engine.start()
                Log("AudioRecorder engine pre-warmed for 1s...")
                try await Task.sleep(nanoseconds: 1_000_000_000)
                engine.stop()
                teardownGraph()
                Log("AudioRecorder engine stopped after pre-warm (indicator off)")
            } catch {
                Log("AudioRecorder pre-warm engine start failed: \(error)", level: .error)
                teardownGraph()
            }
            recordSystemAudio = savedSysAudio
        }
    }

    // MARK: - Public Methods

    /// Checks if screen capture permission is granted.
    public func hasScreenCapturePermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    /// Requests screen capture permission from the user (opens System Settings).
    public func requestScreenCapturePermission() {
        CGRequestScreenCaptureAccess()
    }

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

        // If system audio is requested, verify screen capture permission first
        if recordSystemAudio {
            guard hasScreenCapturePermission() else {
                Log("Screen capture permission denied — cannot record system audio", level: .error)
                throw AudioRecorderError.screenCapturePermissionDenied
            }
        }

        // Rebuild graph if system audio config changed since last setup
        if graphInitialized && graphIncludesSystemAudio != recordSystemAudio {
            Log("System audio config changed, rebuilding graph...")
            teardownGraph()
        }

        setupGraph()

        // 1. Ensure engine is running
        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
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
            sysPlayerNode?.play()
        }

        // 3. Get the ACTUAL output format of the recording mixer AFTER engine is running.
        // This MUST match the hardware sample rate or installTap will crash.
        guard let mixer = recordingMixer else {
            throw AudioRecorderError.setupFailed
        }

        let tapFormat = mixer.outputFormat(forBus: 0)
        Log("Tap format: \(tapFormat.sampleRate)Hz, \(tapFormat.channelCount)ch")

        // 4. Create File with the native format (NOT 16kHz!)
        let fileURL = getNewRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: tapFormat.sampleRate,
            AVNumberOfChannelsKey: tapFormat.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
            Log("Created WAV file: \(tapFormat.sampleRate)Hz \(tapFormat.channelCount)ch — \(fileURL.path)")
        } catch {
            Log("Failed to create audio file: \(error)", level: .error)
            throw AudioRecorderError.setupFailed
        }

        // 5. Install Tap — use nil format to match the node's native output format.
        // This avoids the fatal "format.sampleRate == inputHWFormat.sampleRate" crash.
        if tapInstalled {
            mixer.removeTap(onBus: 0)
            tapInstalled = false
        }

        mixer.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, time in
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

        if let mixer = recordingMixer {
            mixer.removeTap(onBus: 0)
        }
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

        // Stop engine to hide the orange dot
        engine.stop()
        teardownGraph()

        return url
    }

    // MARK: - Private Helpers

    private func teardownGraph() {
        guard graphInitialized else { return }

        if let mixer = recordingMixer {
            engine.disconnectNodeInput(mixer)
            engine.disconnectNodeOutput(mixer)
            engine.detach(mixer)
        }

        if let mic = micMixer {
            engine.disconnectNodeInput(mic)
            engine.disconnectNodeOutput(mic)
            engine.detach(mic)
        }

        if let player = sysPlayerNode {
            engine.disconnectNodeInput(player)
            engine.disconnectNodeOutput(player)
            engine.detach(player)
            sysPlayerNode = nil
        }

        recordingMixer = nil
        micMixer = nil
        graphInitialized = false
        graphIncludesSystemAudio = false
        Log("AudioRecorder graph torn down")
    }

    private func setupGraph() {
        guard !graphInitialized else { return }

        Log("Initializing AudioRecorder graph (systemAudio: \(recordSystemAudio))...")

        let recMixer = AVAudioMixerNode()
        let mMixer = AVAudioMixerNode()
        self.recordingMixer = recMixer
        self.micMixer = mMixer

        let mainMixer = engine.mainMixerNode
        mainMixer.outputVolume = 0.0

        engine.attach(recMixer)
        engine.attach(mMixer)

        // Use native input format — do NOT force 16kHz
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        Log("Hardware input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        // Mic → micMixer → recordingMixer
        engine.connect(inputNode, to: mMixer, format: inputFormat)
        mMixer.pan = -1.0 // Left channel
        engine.connect(mMixer, to: recMixer, format: inputFormat)

        // System Audio → recordingMixer (only if enabled)
        if recordSystemAudio {
            if #available(macOS 12.3, *) {
                let sysFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
                let player = AVAudioPlayerNode()
                engine.attach(player)
                player.pan = 1.0 // Right channel
                engine.connect(player, to: recMixer, format: sysFormat)
                self.sysPlayerNode = player
            }
        }

        // recordingMixer → mainMixer (using input format to keep sample rates consistent)
        engine.connect(recMixer, to: mainMixer, format: inputFormat)

        graphInitialized = true
        graphIncludesSystemAudio = recordSystemAudio
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
