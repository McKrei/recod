import SwiftUI
import SwiftData

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    // Configuration
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

    public var escapeCancelsRecording: Bool {
        get {
            if UserDefaults.standard.object(forKey: "escapeCancelsRecording") == nil {
                UserDefaults.standard.set(true, forKey: "escapeCancelsRecording")
            }
            return UserDefaults.standard.bool(forKey: "escapeCancelsRecording")
        }
        set {
            self.objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "escapeCancelsRecording")
        }
    }

    public var selectedEngine: TranscriptionEngine {
        get {
            TranscriptionEngine(rawValue: UserDefaults.standard.string(forKey: "selectedEngine") ?? "whisperKit") ?? .whisperKit
        }
        set {
            self.objectWillChange.send()
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectedEngine")
        }
    }

    public var defaultPostProcessingSystemPrompt: String {
        get {
            let value = UserDefaults.standard.string(forKey: "defaultPostProcessingSystemPrompt")?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let value, !value.isEmpty {
                return value
            }

            return PostProcessingPromptDefaults.systemPrompt
        }
        set {
            self.objectWillChange.send()

            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let valueToStore = trimmed.isEmpty ? PostProcessingPromptDefaults.systemPrompt : trimmed
            UserDefaults.standard.set(valueToStore, forKey: "defaultPostProcessingSystemPrompt")
        }
    }

    // Dependencies
    public var modelContext: ModelContext? {
        didSet {
            RecordingOrchestrator.shared.modelContext = modelContext
        }
    }

    public let whisperModelManager = WhisperModelManager()
    public let parakeetModelManager = ParakeetModelManager()

    init() {
        RecordingOrchestrator.shared.whisperModelManager = whisperModelManager
        RecordingOrchestrator.shared.parakeetModelManager = parakeetModelManager

        setupHotKey()
    }

    private func setupHotKey() {
        HotKeyManager.shared.onTrigger = { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }
        HotKeyManager.shared.registerDefault()
    }

    func prepareAudio() {
        RecordingOrchestrator.shared.prepareAudio()
    }

    func toggleRecording() {
        RecordingOrchestrator.shared.toggleRecording(
            recordSystemAudio: recordSystemAudio,
            saveToClipboard: saveToClipboard,
            selectedEngine: selectedEngine
        )
    }

    func revealLogs() {
        Task { await FileLogger.shared.revealLogsInFinder() }
    }

    func revealRecordings() {
        RecordingOrchestrator.shared.revealRecordings()
    }

    func retranscribe(_ recording: Recording) {
        RecordingOrchestrator.shared.retranscribe(recording: recording)
    }

    func cancelRetranscribe(_ recording: Recording) {
        RecordingOrchestrator.shared.cancelRetranscribe(recording: recording)
    }

    func runManualPostProcessing(recording: Recording, action: PostProcessingAction) {
        RecordingOrchestrator.shared.runManualPostProcessing(recording: recording, action: action)
    }

    func copyTextToClipboard(_ text: String) {
        ClipboardService.shared.copyToClipboard(text)
    }
}
