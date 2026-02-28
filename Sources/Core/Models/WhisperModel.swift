import Foundation

enum WhisperModelType: String, CaseIterable, Identifiable, Codable, Sendable {
    case tiny = "openai_whisper-tiny"
    case base = "openai_whisper-base"
    case small = "openai_whisper-small"
    case medium = "openai_whisper-medium"
    case largeV3 = "openai_whisper-large-v3"
    case largeV3Turbo = "openai_whisper-large-v3_turbo"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .tiny: return "Tiny"
        case .base: return "Base"
        case .small: return "Small"
        case .medium: return "Medium"
        case .largeV3: return "Large v3"
        case .largeV3Turbo: return "Large v3 Turbo"
        }
    }
    
    var variantName: String {
        rawValue.replacingOccurrences(of: "openai_whisper-", with: "")
    }
    
    var filename: String {
        rawValue
    }
    
    var approximateSize: String {
        switch self {
        case .tiny: return "40 MB"
        case .base: return "80 MB"
        case .small: return "250 MB"
        case .medium: return "800 MB"
        case .largeV3: return "1.6 GB"
        case .largeV3Turbo: return "900 MB"
        }
    }
    
    var languages: String {
        "99 languages (en, ru, de, fr, es, it, zh, ja...)"
    }
}

struct WhisperModel: Identifiable, Equatable, Sendable {
    let type: WhisperModelType
    var id: String { type.id }
    
    var name: String { type.displayName }
    var sizeDescription: String { type.approximateSize }
    
    var isDownloaded: Bool = false
    var isDownloading: Bool = false
    var downloadProgress: Double = 0.0
}
