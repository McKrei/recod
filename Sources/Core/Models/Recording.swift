import Foundation
import SwiftData

@Model
final class Recording {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var transcription: String?
    var filename: String
    
    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        duration: TimeInterval = 0,
        transcription: String? = nil,
        filename: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.transcription = transcription
        self.filename = filename
    }
    
    @Transient
    var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("MacAudio2/Recordings", isDirectory: true)
        return directory.appendingPathComponent(filename)
    }
}
