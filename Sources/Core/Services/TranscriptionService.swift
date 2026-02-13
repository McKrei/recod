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
            whisperKit = try await WhisperKit(modelFolder: modelURL.path)
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
        
        await FileLogger.shared.log("Starting WhisperKit inference...")
        let inferStart = Date()
        
        // 1. Detect language first using the path
        var detectedLang = "en"
        // detectLanguage returns (language: String, langProbs: [String: Float])
        let detectionResult = try await kit.detectLanguage(audioPath: audioURL.path)
        
        // Use the top detected language
        detectedLang = detectionResult.language
        let prob = detectionResult.langProbs[detectedLang] ?? 0.0
        await FileLogger.shared.log("Detected language: \(detectedLang) (prob: \(prob))")
        
        // 2. Force transcription with the detected language
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
    
    func clearCache() {
        whisperKit = nil
        currentModelURL = nil
    }
}
