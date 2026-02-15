import Foundation
import SwiftUI
import Observation
import WhisperKit

@MainActor
@Observable
final class WhisperModelManager: NSObject {
    var models: [WhisperModel] = []
    var selectedModelId: String? {
        didSet {
            UserDefaults.standard.set(selectedModelId, forKey: "selectedWhisperModelId")
        }
    }
    
    nonisolated private var modelsDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportDir = paths[0].appendingPathComponent("Recod")
        let modelsDir = appSupportDir.appendingPathComponent("Models")
        
        if !FileManager.default.fileExists(atPath: modelsDir.path) {
            try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }
        
        return modelsDir
    }
    
    /// The actual path where WhisperKit stores models relative to downloadBase
    nonisolated private var whisperKitModelsPath: URL {
        modelsDirectory
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
    }
    
    override init() {
        super.init()
        self.selectedModelId = UserDefaults.standard.string(forKey: "selectedWhisperModelId")
        self.loadModels()
    }
    
    private func loadModels() {
        var initialModels = WhisperModelType.allCases.map { type in
            WhisperModel(type: type)
        }
        
        let fileManager = FileManager.default
        for i in 0..<initialModels.count {
            let model = initialModels[i]
            let modelFolder = whisperKitModelsPath.appendingPathComponent(model.type.filename)
            if fileManager.fileExists(atPath: modelFolder.path) {
                initialModels[i].isDownloaded = true
            }
        }
        
        self.models = initialModels
        
        if selectedModelId == nil, let first = models.first {
            selectedModelId = first.id
        }
    }
    
    // MARK: - Actions
    
    func downloadModel(_ model: WhisperModel) {
        guard !model.isDownloading && !model.isDownloaded else { return }
        
        guard let index = models.firstIndex(where: { $0.id == model.id }) else { return }
        models[index].isDownloading = true
        models[index].downloadProgress = 0.0
        
        Task {
            do {
                await FileLogger.shared.log("Starting WhisperKit download for variant: \(model.type.variantName)")
                
                _ = try await WhisperKit.download(
                    variant: model.type.variantName,
                    downloadBase: modelsDirectory,
                    progressCallback: { @Sendable progress in
                        Task { @MainActor in
                            if let idx = self.models.firstIndex(where: { $0.id == model.id }) {
                                self.models[idx].downloadProgress = progress.fractionCompleted
                                // Log progress every 10% to avoid log spam but show activity
                                if Int(progress.fractionCompleted * 100) % 10 == 0 {
                                     // Silent update for UI
                                }
                            }
                        }
                    }
                )
                
                await FileLogger.shared.log("Download successful: \(model.type.variantName)")
                
                await MainActor.run {
                    if let idx = models.firstIndex(where: { $0.id == model.id }) {
                        models[idx].isDownloading = false
                        models[idx].isDownloaded = true
                        models[idx].downloadProgress = 1.0
                    }
                }
            } catch {
                await FileLogger.shared.log("WhisperKit download failed: \(error)", level: .error)
                await MainActor.run {
                    if let idx = models.firstIndex(where: { $0.id == model.id }) {
                        models[idx].isDownloading = false
                        models[idx].downloadProgress = 0.0
                    }
                }
            }
        }
    }
    
    func cancelDownload(_ model: WhisperModel) {
        if let index = models.firstIndex(where: { $0.id == model.id }) {
            models[index].isDownloading = false
            models[index].downloadProgress = 0.0
        }
    }
    
    func deleteModel(_ model: WhisperModel) {
        let modelFolder = whisperKitModelsPath.appendingPathComponent(model.type.filename)
        try? FileManager.default.removeItem(at: modelFolder)
        
        if let index = models.firstIndex(where: { $0.id == model.id }) {
            models[index].isDownloaded = false
            models[index].downloadProgress = 0.0
        }
    }
    
    func selectModel(_ model: WhisperModel) {
        selectedModelId = model.id
        TranscriptionService.shared.clearCache()
    }
    
    // MARK: - Helper Methods
    
    nonisolated public func getModelURL(for modelId: String) -> URL? {
        guard let type = WhisperModelType(rawValue: modelId) else { return nil }
        let url = whisperKitModelsPath.appendingPathComponent(type.filename)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }
}
