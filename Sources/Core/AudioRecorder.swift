@preconcurrency import AVFoundation
import AppKit
import ScreenCaptureKit
import CoreMedia
import Accelerate

public enum AudioRecorderError: Error, LocalizedError {
    case permissionDenied
    case setupFailed
    case recordingFailed
    case screenCapturePermissionDenied
    /// Bluetooth headset switched input to HFP (16 kHz) and the output device
    /// rejected the sample-rate alignment request.  Recording is impossible until
    /// the user selects a different input device (e.g. built-in microphone).
    case bluetoothHFPDetected

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Microphone permission denied"
        case .setupFailed: return "Audio setup failed"
        case .recordingFailed: return "Recording failed"
        case .screenCapturePermissionDenied: return "Screen recording permission is required for system audio capture. Please enable it in System Settings → Privacy & Security → Screen & System Audio Recording."
        case .bluetoothHFPDetected: return "Bluetooth headset is using the phone call (HFP) profile which only supports 16 kHz. Please switch the input device to the built-in microphone in System Settings → Sound → Input."
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

    private var engine: AVAudioEngine?
    private var recordingMixer: AVAudioMixerNode?
    private var micMixer: AVAudioMixerNode?
    private var sysPlayerNode: AVAudioPlayerNode?

    private var audioFile: AVAudioFile?
    private var tapInstalled = false
    private var graphInitialized = false
    private var graphIncludesSystemAudio = false
    private var tapBufferCount: Int = 0

    // Modular Components
    private let streamBuffer = AudioStreamBuffer()
    private let levelMonitor = AudioLevelMonitor()
    private let deviceManager = CoreAudioDeviceManager()

    // System Audio
    private var scStream: SCStream?

    // Config
    public var recordSystemAudio: Bool = false

    /// True while prepareAudio() Task is running. startRecording() waits for it to finish.
    private var isPrewarming = false

    @Published public var isRecording = false
    @Published public private(set) var audioLevel: Float = 0
    public var currentRecordingURL: URL? { audioFile?.url }

    // MARK: - Initializer & Pre-warm

    public override init() {
        super.init()

        // Bind Level Monitor to published state
        levelMonitor.onLevelUpdate = { [weak self] level in
            self?.audioLevel = level
        }
    }

    public func getAudioSamples() -> [Float] {
        streamBuffer.getSamples()
    }

    /// Returns the number of accumulated 16kHz streaming samples without copying the full buffer.
    public func getAudioSampleCount() -> Int {
        streamBuffer.getSampleCount()
    }

    /// Returns the accumulated audio samples added after the specified index.
    /// Useful for streaming transcription to avoid copying the entire buffer repeatedly.
    public func getNewAudioSamples(from index: Int) -> [Float] {
        streamBuffer.getNewSamples(from: index)
    }

    public func clearAudioSamples() {
        streamBuffer.clear()
    }

    /// Prepares the audio engine at app launch so the first recording works immediately.
    ///
    /// Unlike the old prewarm() approach, this method does NOT start and stop the engine —
    /// that pattern caused macOS to "remember" the wrong hardware sample rate, requiring a
    /// second recording attempt to get the correct 48kHz input format.
    ///
    /// Instead we:
    ///   1. Request mic permission (no engine needed)
    ///   2. Align input/output sample rates via CoreAudio (no engine needed)
    ///   3. Build the graph and start the engine — then LEAVE IT RUNNING idle
    ///
    /// The engine sits idle (no tap, no file) until startRecording() installs a tap.
    /// startRecording() sees graphInitialized=true and skips the entire setup/alignment phase.
    public func prepareAudio() {
        isPrewarming = true
        Task {
            // Step 1: request permission without touching AVAudioEngine
            let granted = await requestPermission()
            guard granted else {
                Log("prepareAudio: mic permission denied — skipping graph setup", level: .warning)
                isPrewarming = false
                return
            }

            // Step 2: align rates via CoreAudio before any engine touches the hardware
            let inputRate = deviceManager.defaultInputSampleRate()
            let outputRate = deviceManager.defaultOutputSampleRate()
            if inputRate > 0 && outputRate > 0 && inputRate != outputRate {
                Log("prepareAudio: rate mismatch \(inputRate)Hz input vs \(outputRate)Hz output — aligning")
                let aligned = deviceManager.alignOutputSampleRate(to: inputRate)
                if !aligned {
                    // BT HFP device rejected the rate change. Skip graph setup — it would
                    // silently produce 0 tap buffers. startRecording() will re-attempt
                    // alignment and throw bluetoothHFPDetected with a user-actionable message.
                    Log("prepareAudio: alignOutputSampleRate failed (BT HFP?) — skipping graph setup", level: .warning)
                    isPrewarming = false
                    return
                }
                // Wait for CoreAudio to propagate asynchronously
                try? await Task.sleep(nanoseconds: 300_000_000)
            }

            // Step 3: build graph with mic-only (system audio is added later if needed)
            let savedSysAudio = recordSystemAudio
            recordSystemAudio = false
            setupGraph()
            recordSystemAudio = savedSysAudio

            guard let eng = engine else {
                Log("prepareAudio: engine is nil after setupGraph", level: .error)
                isPrewarming = false
                return
            }

            eng.prepare()
            Log("prepareAudio: engine prepared (not started) — graph ready for recording")

            isPrewarming = false
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

        // Wait for prepareAudio() to finish if it is still running.
        // prepareAudio builds the graph and starts the engine; we must not start a second
        // engine or touch the graph until it completes.
        if isPrewarming {
            Log("startRecording: waiting for prepareAudio() to finish...")
            let deadline = Date().addingTimeInterval(5.0)
            while isPrewarming && Date() < deadline {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            if isPrewarming {
                Log("prepareAudio did not finish in time — proceeding anyway", level: .warning)
            }
        }

        if recordSystemAudio {
            guard hasScreenCapturePermission() else {
                Log("Screen capture permission denied — cannot record system audio", level: .error)
                throw AudioRecorderError.screenCapturePermissionDenied
            }
        }

        // If system-audio config changed since prepareAudio built the graph, rebuild.
        // Also add a short pause so macOS releases hardware before the new engine starts.
        if graphInitialized && graphIncludesSystemAudio != recordSystemAudio {
            Log("System audio config changed — rebuilding graph...")
            engine?.stop()
            teardownGraph()
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        // Only do rate alignment + graph setup if the graph is not already running.
        // In the normal happy path prepareAudio() already did this — graphInitialized=true,
        // engine is started, and we just need to install the tap and open the file.
        if !graphInitialized {
            // CRITICAL: Align output device sample rate BEFORE building the graph.
            // AVAudioEngine reads device sample rates at graph construction time (when inputNode/mainMixerNode
            // are first accessed). If input (BT HFP = 16kHz) != output (A2DP = 44100Hz) at that moment,
            // the engine will silently build a broken render graph — installTap receives zero buffers.
            //
            // IMPORTANT: Do NOT use a probe AVAudioEngine to read rates — accessing inputNode on any
            // AVAudioEngine instance causes macOS to capture the mic hardware. When that probe engine is
            // released and the real engine starts, the mic may still be "held", causing installTap to
            // receive zero buffers. Instead, read rates directly via CoreAudio (no hardware capture).
            let inputRate = deviceManager.defaultInputSampleRate()
            let outputRate = deviceManager.defaultOutputSampleRate()
            if inputRate > 0 && outputRate > 0 && inputRate != outputRate {
                Log("Pre-graph sample rate mismatch: input=\(inputRate)Hz output=\(outputRate)Hz — aligning output BEFORE graph setup")
                let aligned = deviceManager.alignOutputSampleRate(to: inputRate)
                if !aligned {
                    // BT HFP device rejected the rate change. The graph would silently receive
                    // 0 tap buffers. Fail immediately with a user-actionable error instead of
                    // waiting 2 seconds for the watchdog to fire.
                    Log("alignOutputSampleRate failed — Bluetooth HFP active. Aborting recording.", level: .error)
                    throw AudioRecorderError.bluetoothHFPDetected
                }
                // Wait for CoreAudio to propagate the change before AVAudioEngine reads device rates
                try await Task.sleep(nanoseconds: 300_000_000)
            }

            setupGraph()

            guard let eng = engine else { throw AudioRecorderError.setupFailed }
            eng.prepare()
            do {
                try eng.start()
            } catch {
                Log("Engine start failed: \(error)", level: .error)
                throw AudioRecorderError.setupFailed
            }
        } else if graphIncludesSystemAudio != recordSystemAudio {
            // This branch is unreachable here (handled above), but kept as safety net.
            Log("startRecording: graph/sysAudio mismatch after rebuild guard — this is a bug", level: .error)
        }

        guard let engine = engine, let mixer = recordingMixer else {
            throw AudioRecorderError.setupFailed
        }

        let tapFormat = mixer.outputFormat(forBus: 0)
        Log("Tap format: \(tapFormat.sampleRate)Hz, \(tapFormat.channelCount)ch")

        self.streamBuffer.prepare(for: tapFormat)
        self.clearAudioSamples()

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

        if tapInstalled {
            mixer.removeTap(onBus: 0)
            tapInstalled = false
        }

        tapBufferCount = 0
        mixer.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, time in
            guard let self = self else { return }

            // Diagnostic: log first buffer to confirm tap is receiving data
            let count = self.tapBufferCount
            if count == 0 {
                Log("Tap FIRST buffer: \(buffer.frameLength) frames @ \(buffer.format.sampleRate)Hz \(buffer.format.channelCount)ch")
            } else if count == 10 {
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

        // Start engine only if it is not already running (prepareAudio() may have started it).
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                Log("Engine start failed: \(error)", level: .error)
                throw AudioRecorderError.setupFailed
            }
        }

        // Watchdog: verify tap is actually receiving audio within 2 seconds.
        // If BT HFP mismatch fix failed or another OS-level issue occurred, the engine starts
        // without error but installTap silently receives zero buffers. Detect this early so
        // we can fail fast instead of saving an empty WAV file.
        let watchdogDeadline = Date().addingTimeInterval(2.0)
        while tapBufferCount == 0 && Date() < watchdogDeadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if tapBufferCount == 0 {
            Log("Tap watchdog: 0 buffers after 2s — engine render graph is broken. Aborting.", level: .error)
            engine.stop()
            teardownGraph()
            audioFile = nil
            throw AudioRecorderError.recordingFailed
        }

        if recordSystemAudio {
            if #available(macOS 12.3, *) {
                if scStream == nil {
                    try await startSystemAudioCapture()
                }
            }
            sysPlayerNode?.play()
        }

        levelMonitor.startPublishing()

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

        levelMonitor.stopPublishing(resetToZero: true)

        await MainActor.run { self.isRecording = false }
        Log("Recording stopped")

        // Stop engine and fully release graph
        engine?.stop()
        teardownGraph()

        return url
    }

    // MARK: - Private Helpers

    private func teardownGraph() {
        guard graphInitialized else { return }

        deviceManager.restoreOutputSampleRate()
        levelMonitor.stopPublishing(resetToZero: true)

        if let engine = engine {
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
        }

        recordingMixer = nil
        micMixer = nil
        engine = nil // Fully release the engine to free the microphone hardware
        graphInitialized = false
        graphIncludesSystemAudio = false
        Log("AudioRecorder graph torn down (Engine Released)")
    }

    private func setupGraph() {
        guard !graphInitialized else { return }

        Log("Initializing AudioRecorder graph (systemAudio: \(recordSystemAudio))...")

        let newEngine = AVAudioEngine()
        self.engine = newEngine

        let recMixer = AVAudioMixerNode()
        let mMixer = AVAudioMixerNode()
        self.recordingMixer = recMixer
        self.micMixer = mMixer

        let mainMixer = newEngine.mainMixerNode
        mainMixer.outputVolume = 0.0

        newEngine.attach(recMixer)
        newEngine.attach(mMixer)

        // Use native input format — do NOT force 16kHz.
        // macOS AVAudioEngine strictly requires tap format == hardware input sample rate.
        let inputNode = newEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        Log("Hardware input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        // CRITICAL: All connections in the graph must use inputFormat (hardware input sample rate).
        // Using a different format (e.g. mainMixer's 44100Hz output format) when input is 16kHz HFP
        // causes AVAudioEngine to silently break the render graph — installTap receives zero buffers.
        //
        // For BT HFP (16kHz mono), pan must NOT be set — setting pan on a mono node
        // causes the engine to stall silently (no crash, no error, zero tap buffers).

        // inputNode → micMixer: use hardware input format (required by AVAudioEngine)
        newEngine.connect(inputNode, to: mMixer, format: inputFormat)

        // Pan only for stereo input (e.g. built-in mic or stereo aggregate device)
        if inputFormat.channelCount >= 2 {
            mMixer.pan = -1.0 // Left channel (mic side)
        }

        // micMixer → recordingMixer: use inputFormat to keep the graph consistent
        newEngine.connect(mMixer, to: recMixer, format: inputFormat)

        // System Audio → recordingMixer (only if enabled)
        if recordSystemAudio {
            if #available(macOS 12.3, *) {
                let sysFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                              sampleRate: 48000, channels: 2, interleaved: false)!
                let player = AVAudioPlayerNode()
                newEngine.attach(player)
                if inputFormat.channelCount >= 2 {
                    player.pan = 1.0 // Right channel (system audio side)
                }
                newEngine.connect(player, to: recMixer, format: sysFormat)
                self.sysPlayerNode = player
            }
        }

        // recordingMixer → mainMixer: use inputFormat
        // mainMixerNode handles SRC internally when output device differs
        newEngine.connect(recMixer, to: mainMixer, format: inputFormat)
        Log("Graph connections established. Input: \(inputFormat.sampleRate)Hz \(inputFormat.channelCount)ch")

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
