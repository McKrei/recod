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
@MainActor
public class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    private var audioRecorder: AVAudioRecorder?
    @Published public var isRecording = false
    @Published public var audioLevel: Float = 0.0
    
    private var meteringTimer: Timer?
    
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
        
        let fileURL = getNewRecordingURL()
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            
            guard recorder.record() else {
                throw AudioRecorderError.recordingFailed
            }
            
            self.audioRecorder = recorder
            self.isRecording = true
            startMetering()
            await FileLogger.shared.log("Started recording to \(fileURL.lastPathComponent)")
        } catch {
            await FileLogger.shared.log("Failed to start recording: \(error)", level: .error)
            throw AudioRecorderError.setupFailed
        }
    }
    
    public func stopRecording() async -> URL? {
        stopMetering()
        guard let recorder = audioRecorder, isRecording else { return nil }
        
        recorder.stop()
        self.isRecording = false
        self.audioRecorder = nil
        await FileLogger.shared.log("Stopped recording")
        
        return recorder.url
    }
    
    nonisolated public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if flag {
                await FileLogger.shared.log("Finished recording successfully: \(recorder.url.lastPathComponent)")
            } else {
                await FileLogger.shared.log("Recording finished with error", level: .error)
            }
            // self.isRecording = false // Already handled in stopRecording if stopped manually, but if stopped by system?
            // If stopped by system (e.g. disk full), we need to update state.
            // Check if we are still marked as recording?
            // Actually, audioRecorderDidFinishRecording is called AFTER stop() too.
            // If we called stop(), we set isRecording = false.
            // If system stopped it, isRecording might be true.
            if self.isRecording {
                self.isRecording = false
                self.audioRecorder = nil
            }
        }
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
    public func revealRecordingsInFinder() {
        let fileManager = FileManager.default
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
             let recordingsDir = appSupportURL.appendingPathComponent("MacAudio2/Recordings")
             NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: recordingsDir.path)
        }
    }
    
    private func startMetering() {
        meteringTimer?.invalidate()
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateAudioLevel()
            }
        }
    }
    
    private func stopMetering() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        audioLevel = 0.0
    }
    
    private func updateAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recorder.updateMeters()
        
        // Normalize power from -160..0 dB to 0..1
        let power = recorder.averagePower(forChannel: 0)
        let minDb: Float = -60.0
        
        if power < minDb {
            audioLevel = 0.0
        } else if power >= 0.0 {
            audioLevel = 1.0
        } else {
            // Linearize
            audioLevel = (power - minDb) / (0.0 - minDb)
        }
    }
}
