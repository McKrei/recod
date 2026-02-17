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

    @AppStorage("recordSystemAudio") public var recordSystemAudio: Bool = false

    // Injected by App
    public var modelContext: ModelContext?

    // Shared Services
    public let whisperModelManager = WhisperModelManager()

    private let audioRecorder = AudioRecorder()
    private var cancellables = Set<AnyCancellable>()

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
            // Pre-load model in background if not already loaded
            if let modelId = whisperModelManager.selectedModelId,
               let modelURL = whisperModelManager.getModelURL(for: modelId) {
                Task.detached(priority: .userInitiated) {
                    await TranscriptionService.shared.prepareModel(modelURL: modelURL)
                }
            }

            do {
                overlayStatus = .recording

                // Configure Recorder
                audioRecorder.recordSystemAudio = recordSystemAudio

                try await audioRecorder.startRecording()
                self.isOverlayVisible = true
            } catch {
                await FileLogger.shared.log("Failed to start recording: \(error)", level: .error)
            }
        }
    }

    func stopRecording() {
        Task {
            if let url = await audioRecorder.stopRecording() {
                if let modelId = whisperModelManager.selectedModelId,
                   whisperModelManager.getModelURL(for: modelId) != nil {
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

            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let creationDate = attributes[.creationDate] as? Date ?? Date()

            let recording = Recording(
                createdAt: creationDate,
                duration: duration,
                filename: filename
            )

            modelContext.insert(recording)
            try modelContext.save()

            await FileLogger.shared.log("Saved new recording: \(filename)")

            if let modelId = whisperModelManager.selectedModelId,
               let modelURL = whisperModelManager.getModelURL(for: modelId) {

                recording.transcriptionStatus = .transcribing
                try? modelContext.save()

                do {
                    let (rawText, segments) = try await TranscriptionService.shared.transcribe(audioURL: url, modelURL: modelURL)
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
                    await FileLogger.shared.log("Transcription completed for: \(filename)")

                    ClipboardService.shared.copyToClipboard(finalText)
                    Task {
                        ClipboardService.shared.pasteToActiveApp()
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
            } else {
                recording.transcriptionStatus = .failed
                try? modelContext.save()
                self.isOverlayVisible = false
            }

        } catch {
            await FileLogger.shared.log("Failed to save recording metadata: \(error)", level: .error)
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
