// Sources/Core/Services/ParakeetModelManager.swift

import Foundation
import Observation

// MARK: - Model Type Definitions

enum ParakeetModelType: String, CaseIterable, Identifiable, Codable, Sendable {
    case v3Int8 = "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .v3Int8: return "Parakeet V3 (Int8)"
        }
    }

    var approximateSize: String {
        switch self {
        case .v3Int8: return "640 MB"
        }
    }

    var downloadURL: URL {
        guard let url = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/\(rawValue).tar.bz2") else {
            fatalError("Invalid Parakeet model URL for \(rawValue)")
        }
        return url
    }

    var languages: String { "Fast CPU - 25 languages (en, ru, de...)" }

    /// Directory name inside the extracted archive
    var directoryName: String { rawValue }
}

// MARK: - Model Data

struct ParakeetModel: Identifiable, Equatable, Sendable {
    let type: ParakeetModelType
    var id: String { type.id }
    var name: String { type.displayName }
    var sizeDescription: String { type.approximateSize }
    var isDownloaded: Bool = false
    var isDownloading: Bool = false
    var downloadProgress: Double = 0.0
}

// MARK: - Manager

@MainActor
@Observable
final class ParakeetModelManager: NSObject, @unchecked Sendable {
    var models: [ParakeetModel]
    var isVADDownloaded: Bool = false

    var selectedModelId: String? {
        didSet {
            if let selectedModelId {
                UserDefaults.standard.set(selectedModelId, forKey: "parakeetSelectedModelId")
            } else {
                UserDefaults.standard.removeObject(forKey: "parakeetSelectedModelId")
            }
        }
    }

    private let modelsDirectory: URL
    private let vadDownloadURL = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx")!
    private var activeDownloadTask: URLSessionDownloadTask?
    private var downloadObservation: NSKeyValueObservation?

    override init() {
        // ~/Library/Application Support/Recod/Models/parakeet/
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportDir = paths[0].appendingPathComponent("Recod")
        self.modelsDirectory = appSupportDir.appendingPathComponent("Models").appendingPathComponent("parakeet")

        self.models = ParakeetModelType.allCases.map { ParakeetModel(type: $0) }
        self.selectedModelId = UserDefaults.standard.string(forKey: "parakeetSelectedModelId")

        super.init()

        ensureDirectoryExists()
        checkDownloadedModels()
    }

    // MARK: - Directory Management

    private func ensureDirectoryExists() {
        if !FileManager.default.fileExists(atPath: modelsDirectory.path) {
            try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        }
    }

    private func checkDownloadedModels() {
        let fileManager = FileManager.default

        for i in 0..<models.count {
            let modelDir = modelsDirectory.appendingPathComponent(models[i].type.directoryName)
            let encoderPath = modelDir.appendingPathComponent("encoder.int8.onnx")
            models[i].isDownloaded = fileManager.fileExists(atPath: encoderPath.path)
        }

        let vadPath = modelsDirectory.appendingPathComponent("silero_vad.onnx")
        isVADDownloaded = fileManager.fileExists(atPath: vadPath.path)

        // Auto-select first downloaded model if none selected (fixes bug for previously downloaded models)
        if selectedModelId == nil {
            if let downloadedModel = models.first(where: { $0.isDownloaded }) {
                selectedModelId = downloadedModel.id
            }
        }
    }

    // MARK: - Selection

    func selectModel(_ model: ParakeetModel) {
        guard model.isDownloaded else { return }
        self.selectedModelId = model.id
    }

    // MARK: - Download

    func downloadModel(_ model: ParakeetModel) {
        guard !model.isDownloading, !model.isDownloaded else { return }
        guard let index = models.firstIndex(where: { $0.id == model.id }) else { return }

        models[index].isDownloading = true
        models[index].downloadProgress = 0.0

        Task {
            await FileLogger.shared.log("Starting Parakeet model download: \(model.type.displayName)")

            do {
                // Step 1: Download tar.bz2
                let archivePath = try await downloadFile(
                    from: model.type.downloadURL,
                    modelIndex: index
                )

                // Step 2: Extract
                await MainActor.run {
                    if let idx = self.models.firstIndex(where: { $0.id == model.id }) {
                        self.models[idx].downloadProgress = 0.95 // Extracting phase
                    }
                }

                try await extractArchive(at: archivePath, to: modelsDirectory)

                // Step 3: Clean up archive
                try? FileManager.default.removeItem(at: archivePath)

                // Step 4: Download VAD model if needed
                if !isVADDownloaded {
                    try await downloadVADModel()
                }

                await FileLogger.shared.log("Parakeet model download and extraction complete: \(model.type.displayName)")

                await MainActor.run {
                    if let idx = self.models.firstIndex(where: { $0.id == model.id }) {
                        self.models[idx].isDownloading = false
                        self.models[idx].isDownloaded = true
                        self.models[idx].downloadProgress = 1.0
                    }
                    self.isVADDownloaded = true
                    
                    if self.selectedModelId == nil {
                        self.selectedModelId = model.id
                    }
                }
            } catch {
                await FileLogger.shared.log("Parakeet model download failed: \(error)", level: .error)
                await MainActor.run {
                    if let idx = self.models.firstIndex(where: { $0.id == model.id }) {
                        self.models[idx].isDownloading = false
                        self.models[idx].downloadProgress = 0.0
                    }
                }
            }
        }
    }

    func cancelDownload(_ model: ParakeetModel) {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        downloadObservation?.invalidate()
        downloadObservation = nil

        if let index = models.firstIndex(where: { $0.id == model.id }) {
            models[index].isDownloading = false
            models[index].downloadProgress = 0.0
        }
    }

    func deleteModel(_ model: ParakeetModel) {
        let modelDir = modelsDirectory.appendingPathComponent(model.type.directoryName)
        try? FileManager.default.removeItem(at: modelDir)

        if let index = models.firstIndex(where: { $0.id == model.id }) {
            models[index].isDownloaded = false
            models[index].downloadProgress = 0.0
        }

        // Clear cached recognizer so it doesn't reference deleted files
        ParakeetTranscriptionService.shared.clearCache()
    }

    // MARK: - Path Accessors

    nonisolated func getModelDirectory(for modelId: String) -> URL? {
        guard let type = ParakeetModelType(rawValue: modelId) else { return nil }
        let dir = modelsDirectory.appendingPathComponent(type.directoryName)
        let encoder = dir.appendingPathComponent("encoder.int8.onnx")
        return FileManager.default.fileExists(atPath: encoder.path) ? dir : nil
    }

    nonisolated func getVADModelPath() -> URL? {
        let path = modelsDirectory.appendingPathComponent("silero_vad.onnx")
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    // MARK: - Private Helpers

    private func downloadFile(from url: URL, modelIndex: Int) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = URLSession(configuration: .default)
            let task = session.downloadTask(with: url) { tempURL, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tempURL = tempURL else {
                    continuation.resume(throwing: ParakeetModelError.downloadFailed)
                    return
                }
                // Move to a stable temp location
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".tar.bz2")
                do {
                    try FileManager.default.moveItem(at: tempURL, to: dest)
                    continuation.resume(returning: dest)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            // Observe progress
            self.downloadObservation = task.progress.observe(\.fractionCompleted) { progress, _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    // Scale download progress to 0.0-0.90 (0.90-1.0 reserved for extraction)
                    if modelIndex < self.models.count {
                        self.models[modelIndex].downloadProgress = progress.fractionCompleted * 0.90
                    }
                }
            }

            self.activeDownloadTask = task
            task.resume()
        }
    }

    private func extractArchive(at archivePath: URL, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["xjf", archivePath.path, "-C", destination.path]

            let pipe = Pipe()
            process.standardError = pipe

            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown extraction error"
                    continuation.resume(throwing: ParakeetModelError.extractionFailed(errorMessage))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func downloadVADModel() async throws {
        let (tempURL, _) = try await URLSession.shared.download(from: vadDownloadURL)
        let destPath = modelsDirectory.appendingPathComponent("silero_vad.onnx")
        if FileManager.default.fileExists(atPath: destPath.path) {
            try FileManager.default.removeItem(at: destPath)
        }
        try FileManager.default.moveItem(at: tempURL, to: destPath)
    }
}

// MARK: - Errors

enum ParakeetModelError: LocalizedError {
    case downloadFailed
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "Failed to download Parakeet model."
        case .extractionFailed(let message):
            return "Failed to extract model archive: \(message)"
        }
    }
}
