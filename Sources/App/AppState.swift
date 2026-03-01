//
//  AppState.swift
//  Recod
//
//  Created for OpenCode.
//

import SwiftUI
import Combine
import SwiftData
import AVFoundation

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    enum OverlayStatus {
        case recording
        case transcribing
        case success
        case error
    }

    @Published public var isRecording = false
    @Published public var isOverlayVisible = false
    @Published public var overlayStatus: OverlayStatus = .recording

    public var saveToClipboard: Bool {
        get {
            if UserDefaults.standard.object(forKey: "saveToClipboard") == nil {
                UserDefaults.standard.set(true, forKey: "saveToClipboard")
            }
            return UserDefaults.standard.bool(forKey: "saveToClipboard")
        }
        set {
            self.objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "saveToClipboard")
        }
    }

    public var recordSystemAudio: Bool {
        get { UserDefaults.standard.bool(forKey: "recordSystemAudio") }
        set {
            self.objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "recordSystemAudio")
        }
    }

    // Injected by App
    public var modelContext: ModelContext?

    // Shared Services
    public let whisperModelManager = WhisperModelManager()
    public let parakeetModelManager = ParakeetModelManager()

    public var selectedEngine: TranscriptionEngine {
        get {
            TranscriptionEngine(rawValue: UserDefaults.standard.string(forKey: "selectedEngine") ?? "whisperKit") ?? .whisperKit
        }
        set {
            self.objectWillChange.send()
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectedEngine")
        }
    }

    private let audioRecorder = AudioRecorder()
    private var cancellables = Set<AnyCancellable>()
    private var streamingRecording: Recording?

    init() {
        setupHotKey()
        setupBindings()
    }

    private func setupBindings() {
        // Sync AudioRecorder state to AppState
        audioRecorder.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] recording in
                self?.isRecording = recording
            }
            .store(in: &cancellables)
    }

    func setupHotKey() {
        HotKeyManager.shared.onTrigger = { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }
        HotKeyManager.shared.registerDefault()
    }

    /// Pre-warms the audio recorder to avoid "cold start" delays.
    func prewarmAudio() {
        audioRecorder.prewarm()
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        Task {
            // Verify that the selected engine has a downloaded model before recording
            let engineReady: Bool
            switch selectedEngine {
            case .whisperKit:
                engineReady = whisperModelManager.selectedModelId != nil
                    && whisperModelManager.getModelURL(for: whisperModelManager.selectedModelId ?? "") != nil
            case .parakeet:
                engineReady = parakeetModelManager.selectedModelId != nil
                    && parakeetModelManager.models.first(where: { $0.id == parakeetModelManager.selectedModelId })?.isDownloaded == true
                    && parakeetModelManager.getVADModelPath() != nil
            }

            if !engineReady {
                await FileLogger.shared.log(
                    "Cannot start recording: \(selectedEngine.displayName) model not downloaded.",
                    level: .error
                )
                overlayStatus = .error
                isOverlayVisible = true
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                isOverlayVisible = false
                return
            }

            // Pre-load model in background based on selected engine
            switch selectedEngine {
            case .whisperKit:
                if let modelId = whisperModelManager.selectedModelId,
                   let modelURL = whisperModelManager.getModelURL(for: modelId) {
                    Task.detached(priority: .userInitiated) {
                        await TranscriptionService.shared.prepareModel(modelURL: modelURL)
                    }
                }
            case .parakeet:
                if let modelId = parakeetModelManager.selectedModelId,
                   let modelDir = parakeetModelManager.getModelDirectory(for: modelId) {
                    Task.detached(priority: .userInitiated) {
                        await ParakeetTranscriptionService.shared.prepareModel(modelDir: modelDir)
                    }
                }
            }

            do {
                overlayStatus = .recording

                // Configure Recorder
                audioRecorder.recordSystemAudio = recordSystemAudio

                try await audioRecorder.startRecording()
                self.isOverlayVisible = true

                if let url = audioRecorder.currentRecordingURL, let modelContext = modelContext {
                    let recording = Recording(
                        transcriptionStatus: .streamingTranscription,
                        filename: url.lastPathComponent,
                        transcriptionEngine: selectedEngine.rawValue
                    )
                    modelContext.insert(recording)
                    try? modelContext.save()

                    self.streamingRecording = recording

                    // Start streaming transcription based on selected engine
                    switch selectedEngine {
                    case .whisperKit:
                        if let modelId = whisperModelManager.selectedModelId,
                           let modelURL = whisperModelManager.getModelURL(for: modelId) {
                            StreamingTranscriptionService.shared.startStreaming(
                                recording: recording,
                                audioRecorder: audioRecorder,
                                modelContext: modelContext,
                                modelURL: modelURL
                            )
                        }
                    case .parakeet:
                        if let modelId = parakeetModelManager.selectedModelId,
                           let modelDir = parakeetModelManager.getModelDirectory(for: modelId),
                           let vadPath = parakeetModelManager.getVADModelPath() {
                            ParakeetStreamingService.shared.startStreaming(
                                recording: recording,
                                audioRecorder: audioRecorder,
                                modelContext: modelContext,
                                modelDir: modelDir,
                                vadModelPath: vadPath
                            )
                        }
                    }
                }
            } catch {
                await FileLogger.shared.log("Failed to start recording: \(error)", level: .error)
            }
        }
    }

    func stopRecording() {
        Task {
            // Stop BOTH streaming services to prevent leaks if the user switched engines mid-recording
            StreamingTranscriptionService.shared.stopStreaming()
            let _ = ParakeetStreamingService.shared.flushAndCollectRemaining()
            ParakeetStreamingService.shared.stopStreaming()

            if let url = await audioRecorder.stopRecording() {
                let hasModel: Bool
                switch selectedEngine {
                case .whisperKit:
                    if let modelId = whisperModelManager.selectedModelId,
                       whisperModelManager.getModelURL(for: modelId) != nil {
                        hasModel = true
                    } else {
                        hasModel = false
                    }
                case .parakeet:
                    hasModel = parakeetModelManager.selectedModelId != nil
                        && parakeetModelManager.models.first(where: { $0.id == parakeetModelManager.selectedModelId })?.isDownloaded == true
                }

                if hasModel {
                    overlayStatus = .transcribing
                    await saveRecording(url: url)
                } else {
                    self.isOverlayVisible = false
                    await saveRecording(url: url)
                }
            } else {
                self.isOverlayVisible = false
            }
        }
    }

    private func saveRecording(url: URL) async {
        guard let modelContext = modelContext else {
            await FileLogger.shared.log("ModelContext not set in AppState", level: .error)
            self.isOverlayVisible = false
            return
        }

        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let filename = url.lastPathComponent

            let recording: Recording
            if let existing = self.streamingRecording, existing.filename == filename {
                recording = existing
                recording.duration = duration
                self.streamingRecording = nil
            } else {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let creationDate = attributes[.creationDate] as? Date ?? Date()
                recording = Recording(
                    createdAt: creationDate,
                    duration: duration,
                    filename: filename
                )
                modelContext.insert(recording)
            }

            try modelContext.save()

            await FileLogger.shared.log("Saved new recording: \(filename)")

            // Run batch transcription based on selected engine
            await runBatchTranscription(recording: recording, url: url, modelContext: modelContext)

        } catch {
            await FileLogger.shared.log("Failed to save recording metadata: \(error)", level: .error)
            self.isOverlayVisible = false
        }
    }

    // MARK: - Batch Transcription

    private func runBatchTranscription(recording: Recording, url: URL, modelContext: ModelContext) async {
        recording.transcriptionStatus = .transcribing
        try? modelContext.save()

        do {
            let rawText: String
            let segments: [TranscriptionSegment]
            
            switch selectedEngine {
            case .whisperKit:
                guard let modelId = whisperModelManager.selectedModelId,
                      let modelURL = whisperModelManager.getModelURL(for: modelId) else {
                    throw NSError(domain: "Recod", code: 1, userInfo: [NSLocalizedDescriptionKey: "WhisperKit model not ready"])
                }
                (rawText, segments) = try await TranscriptionService.shared.transcribe(audioURL: url, modelURL: modelURL)
                
            case .parakeet:
                guard let modelId = parakeetModelManager.selectedModelId,
                      parakeetModelManager.models.first(where: { $0.id == modelId })?.isDownloaded == true,
                      let modelDir = parakeetModelManager.getModelDirectory(for: modelId) else {
                    throw NSError(domain: "Recod", code: 1, userInfo: [NSLocalizedDescriptionKey: "Parakeet model not ready"])
                }
                (rawText, segments) = try await ParakeetTranscriptionService.shared.transcribe(audioURL: url, modelDir: modelDir)
            }

            recording.segments = segments

            // Apply text replacements
            var finalText = rawText
            let descriptor = FetchDescriptor<ReplacementRule>()
            do {
                let rules = try modelContext.fetch(descriptor)
                if !rules.isEmpty {
                    await FileLogger.shared.log("Applying \(rules.count) replacement rules...")
                    let original = finalText
                    finalText = TextReplacementService.applyReplacements(text: rawText, rules: rules)

                    if original != finalText {
                        await FileLogger.shared.log("Replacements applied. Text changed.")
                    } else {
                        await FileLogger.shared.log("Replacements applied but text remained unchanged.")
                    }
                }
            } catch {
                await FileLogger.shared.log("Failed to fetch replacement rules: \(error)", level: .error)
            }

            recording.transcription = finalText
            recording.transcriptionStatus = .completed
            try modelContext.save()

            overlayStatus = .success
            await FileLogger.shared.log("Transcription (\(selectedEngine.displayName)) completed for: \(url.lastPathComponent)")

            let shouldSaveToClipboard = self.saveToClipboard
            Task {
                await ClipboardService.shared.insertText(finalText, preserveClipboard: !shouldSaveToClipboard)
            }

            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.isOverlayVisible = false
            
        } catch {
            recording.transcriptionStatus = .failed
            try? modelContext.save()

            overlayStatus = .error
            await FileLogger.shared.log("Transcription failed: \(error)", level: .error)

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.isOverlayVisible = false
        }
    }

    func revealLogs() {
        Task { await FileLogger.shared.revealLogsInFinder() }
    }

    func revealRecordings() {
        audioRecorder.revealRecordingsInFinder()
    }
}
