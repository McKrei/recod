//
//  AppState.swift
//  MacAudio2
//
//  Created for OpenCode.
//

import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var isRecording = false
    @Published var isOverlayVisible = false
    @Published var audioLevel: Float = 0.0
    
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
            
        audioRecorder.$audioLevel
            .receive(on: RunLoop.main)
            .assign(to: \.audioLevel, on: self)
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
            _ = await audioRecorder.stopRecording()
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
