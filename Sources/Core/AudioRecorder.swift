//
//  AudioRecorder.swift
//  MacAudio2
//
//  Created for OpenCode.
//

import AVFoundation
import AppKit

public enum AudioRecorderError: Error {
    case permissionDenied
    case setupFailed
    case recordingFailed
}

/// Actor managing audio recording state and file handling.
public class AudioRecorder: NSObject, ObservableObject, @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?

    @Published public var isRecording = false
    @Published public var audioLevel: Float = 0.0

    // Config
    private let bufferSize: UInt32 = 1024

    public func requestPermission() async -> Bool {
        if #available(macOS 14.0, *) {
            return await AVCaptureDevice.requestAccess(for: .audio)
        } else {
             return await withCheckedContinuation { continuation in
                 AVCaptureDevice.requestAccess(for: .audio) { granted in
                     continuation.resume(returning: granted)
                 }
             }
        }
    }

    public func startRecording() async throws {
        let granted = await requestPermission()
        guard granted else {
            throw AudioRecorderError.permissionDenied
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Setup file for writing
        let fileURL = getNewRecordingURL()
        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
            Log("Created audio file at: \(fileURL.path)")
        } catch {
            Log("Failed to create audio file: \(error)", level: .error)
            throw AudioRecorderError.setupFailed
        }

        // Install tap on input node
        // NOTE: We use a smaller buffer size for smoother UI updates, but installTap might enforce its own size
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, time in
            guard let self = self else { return }

            // 1. Write to file
            do {
                try self.audioFile?.write(from: buffer)
            } catch {
                print("Error writing to file: \(error)")
            }
            
            let level = self.calculateLevel(buffer: buffer)
            Task { @MainActor in
                self.audioLevel = level
            }
        }

        do {
            try engine.start()
            self.audioEngine = engine
            await MainActor.run {
                self.isRecording = true
            }
            Log("Started audio engine")
        } catch {
            Log("Failed to start audio engine: \(error)", level: .error)
            throw AudioRecorderError.setupFailed
        }
    }

    public func stopRecording() async -> URL? {
        guard let engine = audioEngine, isRecording else { return nil }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let url = audioFile?.url
        audioFile = nil // Close file

        await MainActor.run {
            self.isRecording = false
            self.audioLevel = 0
        }
        self.audioEngine = nil

        Log("Stopped recording")

        return url
    }

    private func calculateLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = UInt32(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<Int(frameLength) {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrt(sum / Float(frameLength))
        return rms
    }

    nonisolated public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
       // Deprecated delegate method
    }

    private func getNewRecordingURL() -> URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let recordingsDir = appSupportURL.appendingPathComponent("MacAudio2/Recordings")

        try? fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let dateString = formatter.string(from: Date())

        return recordingsDir.appendingPathComponent("recording-\(dateString).m4a")
    }

    /// Reveals the recordings folder in Finder
    @MainActor
    public func revealRecordingsInFinder() {
        let fileManager = FileManager.default
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
             let recordingsDir = appSupportURL.appendingPathComponent("MacAudio2/Recordings")
             NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: recordingsDir.path)
        }
    }
}
