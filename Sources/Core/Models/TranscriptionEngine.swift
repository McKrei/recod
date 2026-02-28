// Sources/Core/Models/TranscriptionEngine.swift

/// Represents the available transcription engines.
/// Users select this in Settings → Models.
enum TranscriptionEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    case whisperKit = "whisperKit"
    case parakeet = "parakeet"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisperKit: return "WhisperKit"
        case .parakeet: return "Parakeet V3"
        }
    }

    var description: String {
        switch self {
        case .whisperKit: return "OpenAI Whisper models via CoreML. GPU/ANE accelerated."
        case .parakeet: return "NVIDIA Parakeet TDT 0.6B. Fast CPU inference, 25 languages."
        }
    }

    var iconName: String {
        switch self {
        case .whisperKit: return "waveform.circle"
        case .parakeet: return "cpu"
        }
    }
}
