@preconcurrency import AVFoundation
import AppKit

public enum AudioRecorderError: Error {
    case permissionDenied
    case setupFailed
    case recordingFailed
}

public class AudioRecorder: NSObject, ObservableObject, @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tapInstalled = false

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
        let inputNode = engine.inputNode
        
        let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        
        let fileURL = getNewRecordingURL()
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
            Log("Created 16kHz WAV file: \(fileURL.path)")
        } catch {
            Log("Failed to create audio file: \(error)", level: .error)
            throw AudioRecorderError.setupFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputNode.outputFormat(forBus: 0)) { [weak self] buffer, time in
            guard let self = self, let audioFile = self.audioFile else { return }
            
            let converter = AVAudioConverter(from: buffer.format, to: recordingFormat)!
            let convertedBuffer = AVAudioPCMBuffer(pcmFormat: recordingFormat, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * (recordingFormat.sampleRate / buffer.format.sampleRate)) + 100)!
            
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            
            if let error = error {
                Log("Conversion error: \(error)", level: .error)
                return
            }

            do {
                try audioFile.write(from: convertedBuffer)
            } catch {
                Log("Write error: \(error)", level: .error)
            }
        }
        
        tapInstalled = true

        do {
            engine.prepare()
            try engine.start()
            self.audioEngine = engine
            await MainActor.run { self.isRecording = true }
            Log("Recording started at 16kHz")
        } catch {
            Log("Engine start failed: \(error)", level: .error)
            throw AudioRecorderError.setupFailed
        }
    }

    public func stopRecording() async -> URL? {
        guard let engine = audioEngine, isRecording else { return nil }

        try? await Task.sleep(nanoseconds: 500_000_000)

        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        
        engine.stop()
        let url = audioFile?.url
        audioFile = nil
        
        await MainActor.run { self.isRecording = false }
        self.audioEngine = nil
        Log("Recording stopped and file closed")
        return url
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
