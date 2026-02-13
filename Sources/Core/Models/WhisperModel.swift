import Foundation

enum WhisperModelType: String, CaseIterable, Identifiable, Codable, Sendable {
    case tiny
    case base
    case small
    case medium
    case largeV3 = "large-v3"
    case largeV3Turbo = "large-v3-turbo"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .largeV3: return "Large v3"
        case .largeV3Turbo: return "Large v3 Turbo"
        default: return rawValue.capitalized
        }
    }
    
    var filename: String {
        "ggml-\(rawValue).bin"
    }
    
    var url: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }
    
    var approximateSize: String {
        switch self {
        case .tiny: return "75 MB"
        case .base: return "142 MB"
        case .small: return "466 MB"
        case .medium: return "1.5 GB"
        case .largeV3: return "3.09 GB"
        case .largeV3Turbo: return "1.6 GB"
        }
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
