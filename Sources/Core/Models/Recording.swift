import Foundation
import SwiftData

@Model
final class Recording {
    enum TranscriptionStatus: String, Codable {
        case pending
        case transcribing
        case completed
        case failed
    }

    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var transcription: String?
    var transcriptionStatus: TranscriptionStatus?
    var filename: String
    
    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        duration: TimeInterval = 0,
        transcription: String? = nil,
        transcriptionStatus: TranscriptionStatus? = .pending,
        filename: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.transcription = transcription
        self.transcriptionStatus = transcriptionStatus
        self.filename = filename
    }
    
    @Transient
    var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("Recod/Recordings", isDirectory: true)
        return directory.appendingPathComponent(filename)
    }
}
