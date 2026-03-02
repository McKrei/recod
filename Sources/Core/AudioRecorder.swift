@preconcurrency import AVFoundation
import AppKit
import ScreenCaptureKit
import CoreMedia
import Accelerate
import CoreAudio

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

    private enum LevelMeterConfig {
        static let floorDB: Float = -52
        static let ceilingDB: Float = 0
        static let attack: Float = 0.42
        static let release: Float = 0.14
        static let minimumVisibleLevel: Float = 0.01
        static let silenceRMS: Float = 0.00002
        static let epsilonRMS: Float = 0.000001
        static let shapingPower: Float = 1.18
        static let publishIntervalNanoseconds: UInt64 = 50_000_000
    }

    private var engine: AVAudioEngine?
    private var recordingMixer: AVAudioMixerNode?
    private var micMixer: AVAudioMixerNode?
    private var sysPlayerNode: AVAudioPlayerNode?

    private var audioFile: AVAudioFile?
    private var tapInstalled = false
    private var graphInitialized = false
    private var graphIncludesSystemAudio = false
    private var tapBufferCount: Int = 0

    // Streaming support
    private var audioConverter: AVAudioConverter?
    private var streamFormat16kHz: AVAudioFormat?
    private var streamBuffer: [Float] = []
    private let streamBufferQueue = DispatchQueue(label: "com.recod.streamBufferQueue")

    // UI level signal
    private let audioLevelQueue = DispatchQueue(label: "com.recod.audioLevelQueue")
    private var latestRawAudioLevel: Float = 0
    private var smoothedAudioLevel: Float = 0
    private var audioLevelPublisherTask: Task<Void, Never>?

    // System Audio
    private var scStream: SCStream?

    // CoreAudio output sample rate alignment (BT HFP/A2DP fix)
    private var originalOutputSampleRate: Float64 = 0
    private var outputDeviceIDForRestore: AudioDeviceID = kAudioObjectUnknown

    // Config
    public var recordSystemAudio: Bool = false

    /// True while prepareAudio() Task is running. startRecording() waits for it to finish.
    private var isPrewarming = false

    @Published public var isRecording = false
    @Published public private(set) var audioLevel: Float = 0
    public var currentRecordingURL: URL? { audioFile?.url }

    // MARK: - Initializer & Pre-warm

    public func getAudioSamples() -> [Float] {
        streamBufferQueue.sync { streamBuffer }
    }

    /// Возвращает аудиосэмплы, добавленные после указанного индекса.
    /// Полезно для стримингового распознавания без копирования всего буфера каждый раз.
    public func getNewAudioSamples(from index: Int) -> [Float] {
        streamBufferQueue.sync {
            guard index < streamBuffer.count else { return [] }
            return Array(streamBuffer[index...])
        }
    }

    public func clearAudioSamples() {
        streamBufferQueue.sync { streamBuffer.removeAll() }
    }

    public override init() {
        super.init()
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
            let inputRate = coreAudioDefaultInputSampleRate()
            let outputRate = coreAudioDefaultOutputSampleRate()
            if inputRate > 0 && outputRate > 0 && inputRate != outputRate {
                Log("prepareAudio: rate mismatch \(inputRate)Hz input vs \(outputRate)Hz output — aligning")
                let aligned = alignOutputSampleRate(to: inputRate)
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
            let inputRate = coreAudioDefaultInputSampleRate()
            let outputRate = coreAudioDefaultOutputSampleRate()
            if inputRate > 0 && outputRate > 0 && inputRate != outputRate {
                Log("Pre-graph sample rate mismatch: input=\(inputRate)Hz output=\(outputRate)Hz — aligning output BEFORE graph setup")
                let aligned = alignOutputSampleRate(to: inputRate)
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

        if let format16kHz = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) {
            self.streamFormat16kHz = format16kHz
            self.audioConverter = AVAudioConverter(from: tapFormat, to: format16kHz)
        }
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
            self.processBufferForStreaming(buffer)
            self.processBufferForLevel(buffer)
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

        startAudioLevelPublishing()

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

        stopAudioLevelPublishing(resetToZero: true)

        await MainActor.run { self.isRecording = false }
        Log("Recording stopped")

        // Stop engine and fully release graph
        engine?.stop()
        teardownGraph()

        return url
    }

    // MARK: - Private Helpers

    private func processBufferForStreaming(_ buffer: AVAudioPCMBuffer) {
        guard let converter = audioConverter, let format16kHz = streamFormat16kHz else { return }

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

                streamBufferQueue.async {
                    self.streamBuffer.append(contentsOf: samples)
                }
            }
        }
    }

    private func processBufferForLevel(_ buffer: AVAudioPCMBuffer) {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, let channelData = buffer.floatChannelData else { return }

        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return }

        var channelZeroRMS: Float = 0
        vDSP_rmsqv(channelData[0], 1, &channelZeroRMS, vDSP_Length(frameLength))

        let rms: Float
        if channelZeroRMS > LevelMeterConfig.silenceRMS || channelCount == 1 {
            rms = channelZeroRMS
        } else {
            var sum: Float = 0
            for channel in 0 ..< channelCount {
                var value: Float = 0
                vDSP_rmsqv(channelData[channel], 1, &value, vDSP_Length(frameLength))
                sum += value
            }
            rms = sum / Float(channelCount)
        }

        let safeRMS = max(rms, LevelMeterConfig.epsilonRMS)
        let db = 20 * log10f(safeRMS)
        let clampedDB = min(max(db, LevelMeterConfig.floorDB), LevelMeterConfig.ceilingDB)
        let normalized = (clampedDB - LevelMeterConfig.floorDB) / (LevelMeterConfig.ceilingDB - LevelMeterConfig.floorDB)
        let shaped = powf(min(max(normalized, 0), 1), LevelMeterConfig.shapingPower)

        audioLevelQueue.async { [weak self] in
            self?.latestRawAudioLevel = shaped
        }
    }

    private func startAudioLevelPublishing() {
        stopAudioLevelPublishing(resetToZero: false)

        audioLevelQueue.sync {
            self.latestRawAudioLevel = 0
            self.smoothedAudioLevel = 0
        }

        audioLevelPublisherTask = Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                let publishedValue = self.audioLevelQueue.sync { () -> Float in
                    let target = self.latestRawAudioLevel
                    let coefficient = target > self.smoothedAudioLevel ? LevelMeterConfig.attack : LevelMeterConfig.release
                    self.smoothedAudioLevel += (target - self.smoothedAudioLevel) * coefficient
                    let clamped = min(max(self.smoothedAudioLevel, 0), 1)
                    return clamped < LevelMeterConfig.minimumVisibleLevel ? 0 : clamped
                }

                await MainActor.run {
                    self.audioLevel = publishedValue
                }

                try? await Task.sleep(nanoseconds: LevelMeterConfig.publishIntervalNanoseconds)
            }
        }
    }

    private func stopAudioLevelPublishing(resetToZero: Bool) {
        audioLevelPublisherTask?.cancel()
        audioLevelPublisherTask = nil

        audioLevelQueue.sync {
            self.latestRawAudioLevel = 0
            self.smoothedAudioLevel = 0
        }

        if resetToZero {
            Task { @MainActor [weak self] in
                self?.audioLevel = 0
            }
        }
    }

    private func teardownGraph() {
        guard graphInitialized else { return }

        restoreOutputSampleRate()
        stopAudioLevelPublishing(resetToZero: true)

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

    // MARK: - CoreAudio Output Sample Rate Alignment

    /// Returns the nominal sample rate of the default input device via CoreAudio.
    /// Does NOT create an AVAudioEngine — no microphone hardware is captured.
    private func coreAudioDefaultInputSampleRate() -> Float64 {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &propSize, &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else { return 0 }

        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate = Float64(0)
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(deviceID, &rateAddr, 0, nil, &rateSize, &rate)
        return rate
    }

    /// Returns the nominal sample rate of the default output device via CoreAudio.
    /// Does NOT create an AVAudioEngine — no hardware is captured.
    private func coreAudioDefaultOutputSampleRate() -> Float64 {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &propSize, &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else { return 0 }

        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate = Float64(0)
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(deviceID, &rateAddr, 0, nil, &rateSize, &rate)
        return rate
    }

    /// Aligns the default output device's nominal sample rate to match the input device.
    ///
    /// Problem: When Bluetooth HFP is active, input = 16kHz (HFP) and output = 44100Hz (A2DP).
    /// AVAudioEngine builds an internal aggregate device from default input + output.
    /// If their sample rates differ, the engine starts without error but the render graph
    /// breaks silently — installTap receives zero buffers.
    ///
    /// Solution: force output device to the same sample rate as input before engine.start().
    /// Restore the original rate after recording stops.
    ///
    /// - Returns: `true` if alignment succeeded (or was not needed), `false` if the output
    ///   device rejected the rate change (e.g. Bluetooth HFP).  When `false` is returned the
    ///   caller should throw `AudioRecorderError.bluetoothHFPDetected` immediately instead of
    ///   building the graph — the graph will silently receive 0 tap buffers in this case.
    @discardableResult
    private func alignOutputSampleRate(to targetRate: Float64) -> Bool {
        var outputDeviceID = AudioDeviceID(kAudioObjectUnknown)
        var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultOutputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddr, 0, nil, &propSize, &outputDeviceID
        ) == noErr, outputDeviceID != kAudioObjectUnknown else {
            Log("alignOutputSampleRate: failed to get default output device", level: .error)
            return false
        }

        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var currentRate = Float64(0)
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(outputDeviceID, &rateAddr, 0, nil, &rateSize, &currentRate)

        guard currentRate != targetRate else {
            Log("alignOutputSampleRate: already at \(targetRate)Hz — no change needed")
            originalOutputSampleRate = 0
            outputDeviceIDForRestore = kAudioObjectUnknown
            return true
        }

        Log("alignOutputSampleRate: output \(currentRate)Hz → \(targetRate)Hz (saving for restore)")
        originalOutputSampleRate = currentRate
        outputDeviceIDForRestore = outputDeviceID

        var newRate = targetRate
        let err = AudioObjectSetPropertyData(outputDeviceID, &rateAddr, 0, nil, rateSize, &newRate)
        if err != noErr {
            Log("alignOutputSampleRate: AudioObjectSetPropertyData failed with error \(err) — Bluetooth HFP device rejected rate change", level: .error)
            originalOutputSampleRate = 0
            outputDeviceIDForRestore = kAudioObjectUnknown
            return false
        }
        return true
    }

    private func restoreOutputSampleRate() {
        guard outputDeviceIDForRestore != kAudioObjectUnknown, originalOutputSampleRate > 0 else { return }

        // Check if the target rate is supported by the device.
        // Bluetooth devices in HFP mode do not accept arbitrary sample rates — attempting to set
        // an unsupported rate returns kAudioHardwareUnsupportedOperationError (1852797029).
        var availRatesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(0)
        let sizeErr = AudioObjectGetPropertyDataSize(outputDeviceIDForRestore, &availRatesAddr, 0, nil, &dataSize)
        if sizeErr == noErr && dataSize > 0 {
            let count = Int(dataSize) / MemoryLayout<AudioValueRange>.size
            var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
            AudioObjectGetPropertyData(outputDeviceIDForRestore, &availRatesAddr, 0, nil, &dataSize, &ranges)
            let supported = ranges.contains { range in
                originalOutputSampleRate >= range.mMinimum && originalOutputSampleRate <= range.mMaximum
            }
            if !supported {
                Log("restoreOutputSampleRate: \(originalOutputSampleRate)Hz not supported by output device (likely BT in HFP mode) — skipping restore")
                originalOutputSampleRate = 0
                outputDeviceIDForRestore = kAudioObjectUnknown
                return
            }
        }

        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate = originalOutputSampleRate
        let rateSize = UInt32(MemoryLayout<Float64>.size)
        let err = AudioObjectSetPropertyData(outputDeviceIDForRestore, &rateAddr, 0, nil, rateSize, &rate)
        if err == noErr {
            Log("restoreOutputSampleRate: restored output to \(originalOutputSampleRate)Hz")
        } else {
            Log("restoreOutputSampleRate: failed to restore: \(err)", level: .error)
        }
        originalOutputSampleRate = 0
        outputDeviceIDForRestore = kAudioObjectUnknown
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
