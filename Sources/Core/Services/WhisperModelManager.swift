import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class WhisperModelManager: NSObject, URLSessionDownloadDelegate {
    var models: [WhisperModel] = []
    var selectedModelId: String? {
        didSet {
            UserDefaults.standard.set(selectedModelId, forKey: "selectedWhisperModelId")
        }
    }
    
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var urlSession: URLSession!
    
    nonisolated private var modelsDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportDir = paths[0].appendingPathComponent("MacAudio2")
        let modelsDir = appSupportDir.appendingPathComponent("Models")
        
        if !FileManager.default.fileExists(atPath: modelsDir.path) {
            try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }
        
        return modelsDir
    }
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
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
            let fileURL = modelsDirectory.appendingPathComponent(model.type.filename)
            if fileManager.fileExists(atPath: fileURL.path) {
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
        
        let task = urlSession.downloadTask(with: model.type.url)
        task.taskDescription = model.id
        downloadTasks[model.id] = task
        task.resume()
    }
    
    func cancelDownload(_ model: WhisperModel) {
        if let task = downloadTasks[model.id] {
            task.cancel()
            downloadTasks.removeValue(forKey: model.id)
        }
        
        if let index = models.firstIndex(where: { $0.id == model.id }) {
            models[index].isDownloading = false
            models[index].downloadProgress = 0.0
        }
    }
    
    func deleteModel(_ model: WhisperModel) {
        let fileURL = modelsDirectory.appendingPathComponent(model.type.filename)
        try? FileManager.default.removeItem(at: fileURL)
        
        if let index = models.firstIndex(where: { $0.id == model.id }) {
            models[index].isDownloaded = false
            models[index].downloadProgress = 0.0
        }
    }
    
    func selectModel(_ model: WhisperModel) {
        selectedModelId = model.id
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let modelId = downloadTask.taskDescription else { return }
        
        let destinationURL = getDestinationURL(for: modelId)
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            Task { @MainActor in
                self.completeDownload(for: modelId)
            }
        } catch {
            print("Error moving model file: \(error)")
            Task { @MainActor in
                self.failDownload(for: modelId)
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let modelId = downloadTask.taskDescription else { return }
        
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        
        Task { @MainActor in
            self.updateProgress(for: modelId, progress: progress)
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as? URLError, error.code == .cancelled {
            return
        }
        if let error = error {
            print("Download error: \(error)")
            guard let modelId = task.taskDescription else { return }
            Task { @MainActor in
                self.failDownload(for: modelId)
            }
        }
    }
    
    // MARK: - Helper Methods (MainActor)
    
    nonisolated private func getDestinationURL(for modelId: String) -> URL {
        guard let type = WhisperModelType(rawValue: modelId) else {
             fatalError("Invalid model ID")
        }
        
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportDir = paths[0].appendingPathComponent("MacAudio2")
        let modelsDir = appSupportDir.appendingPathComponent("Models")
        return modelsDir.appendingPathComponent(type.filename)
    }

    @MainActor
    private func updateProgress(for modelId: String, progress: Double) {
        if let index = models.firstIndex(where: { $0.id == modelId }) {
            models[index].downloadProgress = progress
        }
    }
    
    @MainActor
    private func completeDownload(for modelId: String) {
        downloadTasks.removeValue(forKey: modelId)
        if let index = models.firstIndex(where: { $0.id == modelId }) {
            models[index].isDownloading = false
            models[index].isDownloaded = true
            models[index].downloadProgress = 1.0
        }
    }
    
    @MainActor
    private func failDownload(for modelId: String) {
        downloadTasks.removeValue(forKey: modelId)
        if let index = models.firstIndex(where: { $0.id == modelId }) {
            models[index].isDownloading = false
            models[index].downloadProgress = 0.0
        }
    }
}
