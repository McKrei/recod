//
//  AppState.swift
//  MacAudio2
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

    @Published public var isRecording = false
    @Published public var isOverlayVisible = false
    
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
                // If recording stopped externally (e.g. error), hide overlay
                if !recording {
                    self?.isOverlayVisible = false
                }
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

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        Task {
            do {
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
                self.isOverlayVisible = false
                await saveRecording(url: url)
            } else {
                self.isOverlayVisible = false
            }
        }
    }
    
    private func saveRecording(url: URL) async {
        guard let modelContext = modelContext else {
            await FileLogger.shared.log("ModelContext not set in AppState", level: .error)
            return
        }
        
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let filename = url.lastPathComponent
            
            // Get creation date from file attributes
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
        } catch {
            await FileLogger.shared.log("Failed to save recording metadata: \(error)", level: .error)
        }
    }

    func revealLogs() {
        Task { await FileLogger.shared.revealLogsInFinder() }
    }

    func revealRecordings() {
        audioRecorder.revealRecordingsInFinder()
    }
}
