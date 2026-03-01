import Testing
import AVFoundation
import Foundation
import CoreAudio

/// Tests that AVAudioEngine graph actually delivers audio buffers via installTap.
///
/// Run with: swift test --filter AudioEngineGraphTests
///
/// NOTE: All tests run SERIALLY (.serialized) because macOS does not allow
/// multiple AVAudioEngine instances to capture the same hardware input simultaneously.
@Suite(.serialized)
struct AudioEngineGraphTests {

    // MARK: - Minimal graph test (inputNode only, no mixers)

    /// Simplest possible test: tap directly on inputNode, no extra nodes.
    /// If this fails, the issue is at the OS/permission level.
    /// If this passes but other tests fail, the issue is in graph construction.
    @Test("Minimal: direct tap on inputNode receives buffers")
    func minimalDirectTapReceivesBuffers() async throws {
        try await ensureMicPermission()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("[MinimalTap] Input format: \(inputFormat.sampleRate)Hz \(inputFormat.channelCount)ch")

        let bufferCount = LockIsolated(0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            bufferCount.withLock { $0 += 1 }
            if bufferCount.withLock({ $0 }) == 1 {
                print("[MinimalTap] ✅ FIRST buffer: \(buffer.frameLength) frames @ \(buffer.format.sampleRate)Hz \(buffer.format.channelCount)ch")
            }
        }

        engine.prepare()
        try engine.start()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        engine.stop()
        inputNode.removeTap(onBus: 0)

        let count = bufferCount.withLock { $0 }
        print("[MinimalTap] Total buffers: \(count)")

        #expect(count > 0, "Direct inputNode tap received zero buffers. OS-level issue (permission or hardware).")
    }

    // MARK: - Full graph test (mirrors AudioRecorder.setupGraph)

    /// Full graph test: inputNode → micMixer → recMixer → mainMixer, tap on recMixer.
    /// This mirrors the actual AudioRecorder.setupGraph() structure.
    /// Also validates the CoreAudio output sample rate alignment fix for BT HFP/A2DP.
    @Test("Full graph: tap on recordingMixer receives buffers")
    func fullGraphTapReceivesBuffers() async throws {
        try await ensureMicPermission()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let mainMixer = engine.mainMixerNode
        mainMixer.outputVolume = 0.0

        let inputRate = inputFormat.sampleRate
        let outputRate = mainMixer.outputFormat(forBus: 0).sampleRate
        print("[FullGraph] Input format: \(inputRate)Hz \(inputFormat.channelCount)ch")
        print("[FullGraph] MainMixer output format: \(outputRate)Hz \(mainMixer.outputFormat(forBus: 0).channelCount)ch")

        // Apply BT HFP/A2DP fix: align output device sample rate to input before building graph
        if inputRate != outputRate {
            print("[FullGraph] ⚠️ Sample rate mismatch — applying CoreAudio alignment fix")
            alignOutputSampleRateForTest(to: inputRate)
            try await Task.sleep(nanoseconds: 200_000_000) // wait for CoreAudio to apply
        }

        let recMixer = AVAudioMixerNode()
        let micMixer = AVAudioMixerNode()
        engine.attach(recMixer)
        engine.attach(micMixer)

        engine.connect(inputNode, to: micMixer, format: inputFormat)
        if inputFormat.channelCount >= 2 { micMixer.pan = -1.0 }
        engine.connect(micMixer, to: recMixer, format: inputFormat)
        engine.connect(recMixer, to: mainMixer, format: inputFormat)

        print("[FullGraph] recMixer output format after connect: \(recMixer.outputFormat(forBus: 0).sampleRate)Hz \(recMixer.outputFormat(forBus: 0).channelCount)ch")

        let bufferCount = LockIsolated(0)
        var totalFrames: AVAudioFrameCount = 0

        recMixer.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
            bufferCount.withLock { $0 += 1 }
            if bufferCount.withLock({ $0 }) == 1 {
                print("[FullGraph] ✅ FIRST buffer: \(buffer.frameLength) frames @ \(buffer.format.sampleRate)Hz \(buffer.format.channelCount)ch")
            }
            totalFrames += buffer.frameLength
        }

        engine.prepare()
        try engine.start()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        engine.stop()
        recMixer.removeTap(onBus: 0)

        // Restore output sample rate
        if inputRate != outputRate {
            restoreOutputSampleRateForTest(to: outputRate)
        }

        let count = bufferCount.withLock { $0 }
        print("[FullGraph] Total buffers: \(count), frames: \(totalFrames)")

        #expect(count > 0, "recMixer tap received zero buffers. Graph construction is broken.")
        #expect(totalFrames > AVAudioFrameCount(inputRate * 0.5),
                "Less than 0.5s of audio. Expected >\(UInt32(inputRate * 0.5)) frames, got \(totalFrames).")
    }

    // MARK: - WAV file test

    @Test("Recorded WAV file contains audio data (> 10 KB)")
    func recordedFileIsNotEmpty() async throws {
        try await ensureMicPermission()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let mainMixer = engine.mainMixerNode
        mainMixer.outputVolume = 0.0

        // Mirror full AudioRecorder graph: inputNode → micMixer → recMixer → mainMixer
        let recMixer = AVAudioMixerNode()
        let micMixer = AVAudioMixerNode()
        engine.attach(recMixer)
        engine.attach(micMixer)
        engine.connect(inputNode, to: micMixer, format: inputFormat)
        if inputFormat.channelCount >= 2 { micMixer.pan = -1.0 }
        engine.connect(micMixer, to: recMixer, format: inputFormat)
        engine.connect(recMixer, to: mainMixer, format: inputFormat)

        let tapFormat = recMixer.outputFormat(forBus: 0)
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recod_test_\(Int(Date().timeIntervalSince1970)).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: tapFormat.sampleRate,
            AVNumberOfChannelsKey: tapFormat.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
        let audioFile = try AVAudioFile(forWriting: tmpURL, settings: settings)
        print("[WAVTest] Writing to: \(tmpURL.path)")
        print("[WAVTest] Format: \(tapFormat.sampleRate)Hz \(tapFormat.channelCount)ch")

        recMixer.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
            try? audioFile.write(from: buffer)
        }

        engine.prepare()
        try engine.start()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        engine.stop()
        recMixer.removeTap(onBus: 0)
        try await Task.sleep(nanoseconds: 100_000_000) // flush

        let attrs = try FileManager.default.attributesOfItem(atPath: tmpURL.path)
        let fileSize = attrs[.size] as? Int ?? 0
        print("[WAVTest] WAV file size: \(fileSize) bytes")

        // 2s @ 16kHz mono 16-bit = ~64 000 bytes minimum
        // 2s @ 44100Hz mono 16-bit = ~176 400 bytes
        #expect(fileSize > 10_000,
                "WAV file too small: \(fileSize) bytes. Tap received no audio. Expected > 10000 bytes for 2s.")

        try? FileManager.default.removeItem(at: tmpURL)
    }

    // MARK: - Model switch test

    /// Simulates switching transcription model (Whisper → Parakeet → Whisper).
    /// Each model switch triggers stopRecording() + teardownGraph() + a new startRecording().
    /// Regression test for: probeEngine was capturing mic hardware, causing the next
    /// engine to silently receive 0 tap buffers.
    @Test("Two consecutive full graph cycles both receive audio (model-switch regression)")
    func consecutiveGraphCyclesBothReceiveBuffers() async throws {
        try await ensureMicPermission()

        // Run the same graph cycle twice — simulating model switch between recordings
        for cycle in 1...2 {
            print("[CycleTest] --- Cycle \(cycle) START ---")

            // Read rates via CoreAudio (no mic capture, like the fixed startRecording does)
            let inputRate = coreAudioDefaultInputRateForTest()
            let outputRate = coreAudioDefaultOutputRateForTest()
            print("[CycleTest] Cycle \(cycle): input=\(inputRate)Hz output=\(outputRate)Hz")

            if inputRate > 0 && outputRate > 0 && inputRate != outputRate {
                print("[CycleTest] Cycle \(cycle): aligning output rate to input")
                alignOutputSampleRateForTest(to: inputRate)
                try await Task.sleep(nanoseconds: 300_000_000)
            }

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            let mainMixer = engine.mainMixerNode
            mainMixer.outputVolume = 0.0

            let recMixer = AVAudioMixerNode()
            let micMixer = AVAudioMixerNode()
            engine.attach(recMixer)
            engine.attach(micMixer)
            engine.connect(inputNode, to: micMixer, format: inputFormat)
            if inputFormat.channelCount >= 2 { micMixer.pan = -1.0 }
            engine.connect(micMixer, to: recMixer, format: inputFormat)
            engine.connect(recMixer, to: mainMixer, format: inputFormat)

            let bufferCount = LockIsolated(0)
            recMixer.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
                bufferCount.withLock { $0 += 1 }
                if bufferCount.withLock({ $0 }) == 1 {
                    print("[CycleTest] Cycle \(cycle): ✅ FIRST buffer: \(buffer.frameLength) frames @ \(buffer.format.sampleRate)Hz \(buffer.format.channelCount)ch")
                }
            }

            engine.prepare()
            try engine.start()

            // Watchdog: wait up to 2s for first buffer
            let deadline = Date().addingTimeInterval(2.0)
            while bufferCount.withLock({ $0 }) == 0 && Date() < deadline {
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            let count = bufferCount.withLock { $0 }
            print("[CycleTest] Cycle \(cycle) buffers after 2s: \(count)")

            engine.stop()
            recMixer.removeTap(onBus: 0)

            // Restore output rate if we changed it
            if inputRate > 0 && outputRate > 0 && inputRate != outputRate {
                restoreOutputSampleRateForTest(to: outputRate)
            }

            #expect(count > 0,
                "Cycle \(cycle): tap received 0 buffers. Engine re-creation after model switch is broken.")
            print("[CycleTest] --- Cycle \(cycle) END ---")

            // Small pause between cycles (simulates app teardown → new model load → new recording)
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    // MARK: - Helpers

    private func ensureMicPermission() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status != .authorized {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw MicPermissionError()
            }
        }
    }
}

struct MicPermissionError: Error, CustomStringConvertible {
    var description: String { "Microphone permission not granted. Grant access in System Settings → Privacy → Microphone." }
}

/// A simple mutex-protected wrapper for mutation inside closures.
final class LockIsolated<Value>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()

    init(_ value: Value) { self._value = value }

    @discardableResult
    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&_value)
    }
}

// MARK: - CoreAudio helpers for tests

func coreAudioDefaultInputRateForTest() -> Float64 {
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

func coreAudioDefaultOutputRateForTest() -> Float64 {
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

func alignOutputSampleRateForTest(to targetRate: Float64) {
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
    ) == noErr else { return }

    var rateAddr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyNominalSampleRate,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var newRate = targetRate
    let rateSize = UInt32(MemoryLayout<Float64>.size)
    let err = AudioObjectSetPropertyData(outputDeviceID, &rateAddr, 0, nil, rateSize, &newRate)
    print("[CoreAudioHelper] Set output sample rate to \(targetRate)Hz: \(err == noErr ? "OK" : "FAILED (\(err))")")
}

func restoreOutputSampleRateForTest(to rate: Float64) {
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
    ) == noErr else { return }

    var rateAddr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyNominalSampleRate,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var restoreRate = rate
    let rateSize = UInt32(MemoryLayout<Float64>.size)
    let err = AudioObjectSetPropertyData(outputDeviceID, &rateAddr, 0, nil, rateSize, &restoreRate)
    print("[CoreAudioHelper] Restored output sample rate to \(rate)Hz: \(err == noErr ? "OK" : "FAILED (\(err))")")
}
