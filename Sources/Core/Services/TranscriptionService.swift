import Foundation
@preconcurrency import WhisperKit
import AVFoundation

@MainActor
final class TranscriptionService {
    static let shared = TranscriptionService()
    
    private var whisperKit: WhisperKit?
    private var currentModelURL: URL?
    
    private init() {}
    
    func prepareModel(modelURL: URL) async {
        if currentModelURL == modelURL && whisperKit != nil {
            return
        }
        
        await FileLogger.shared.log("Pre-loading WhisperKit model: \(modelURL.lastPathComponent)")
        let start = Date()
        
        do {
            whisperKit = try await WhisperKit(modelFolder: modelURL.path(percentEncoded: false))
            currentModelURL = modelURL
            
            let duration = Date().timeIntervalSince(start)
            await FileLogger.shared.log(String(format: "WhisperKit (CoreML) loaded and cached: %.2fs", duration))
        } catch {
            await FileLogger.shared.log("Failed to load WhisperKit: \(error)", level: .error)
            whisperKit = nil
            currentModelURL = nil
        }
    }
    
    func transcribe(audioURL: URL, modelURL: URL) async throws -> String {
        let startTime = Date()
        await FileLogger.shared.log("--- WhisperKit Transcription Start ---")
        
        if whisperKit == nil || currentModelURL != modelURL {
            await prepareModel(modelURL: modelURL)
        }
        
        guard let kit = whisperKit else {
            throw NSError(domain: "TranscriptionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "WhisperKit not initialized"])
        }
        
        let frameCount = try await waitForFileReady(url: audioURL)
        await FileLogger.shared.log("Audio file verified and ready (\(frameCount) frames)")
        
        await FileLogger.shared.log("Starting WhisperKit inference...")
        let inferStart = Date()
        
        let detectionResult = try await kit.detectLanguage(audioPath: audioURL.path)
        let detectedLang = detectionResult.language
        let prob = detectionResult.langProbs[detectedLang] ?? 0.0
        await FileLogger.shared.log("Detected language: \(detectedLang) (prob: \(prob))")
        
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = detectedLang 
        options.temperature = 0.0
        
        let results = try await kit.transcribe(audioPath: audioURL.path, decodeOptions: options)
        
        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        
        let inferDuration = Date().timeIntervalSince(inferStart)
        let totalDuration = Date().timeIntervalSince(startTime)
        
        await FileLogger.shared.log(String(format: "Inference completed: %.2fs", inferDuration))
        await FileLogger.shared.log(String(format: "Total process time: %.2fs", totalDuration))
        await FileLogger.shared.log("--- Transcription End ---")
        
        return text
    }
    
    private func waitForFileReady(url: URL) async throws -> AVAudioFramePosition {
        var lastError: Error?
        
        for i in 0..<12 {
            do {
                let file = try AVAudioFile(forReading: url)
                let length = file.length
                if length > 0 {
                    return length
                }
            } catch {
                lastError = error
            }

            try? await Task.sleep(nanoseconds: 100_000_000 * UInt64(i + 1))
        }
        
        await FileLogger.shared.log("Audio file is empty after verification.", level: .error)
        throw lastError ?? NSError(domain: "TranscriptionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio samples are empty"])
    }
    
    func clearCache() {
        whisperKit = nil
        currentModelURL = nil
    }
}
