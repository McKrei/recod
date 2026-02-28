import Foundation
import SwiftData

@Model
final class Recording {
    enum TranscriptionStatus: String, Codable {
        case pending
        case streamingTranscription
        case transcribing
        case completed
        case failed
    }

    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var transcription: String?
    var liveTranscription: String?
    var transcriptionStatus: TranscriptionStatus?
    var filename: String
    var isFileDeleted: Bool = false
    var transcriptionEngine: String?

    @Attribute(.externalStorage) var segments: [TranscriptionSegment]?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        duration: TimeInterval = 0,
        transcription: String? = nil,
        liveTranscription: String? = nil,
        transcriptionStatus: TranscriptionStatus? = .pending,
        filename: String,
        isFileDeleted: Bool = false,
        transcriptionEngine: String? = nil,
        segments: [TranscriptionSegment]? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.transcription = transcription
        self.liveTranscription = liveTranscription
        self.transcriptionStatus = transcriptionStatus
        self.filename = filename
        self.isFileDeleted = isFileDeleted
        self.transcriptionEngine = transcriptionEngine
        self.segments = segments
    }


    @Transient
    var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("Recod/Recordings", isDirectory: true)
        return directory.appendingPathComponent(filename)
    }
}

struct TranscriptionSegment: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}
