import Foundation
import SwiftData

// MARK: - Data Transfer Objects (DTO)

struct BackupPayload: Codable {
    let version: Int
    let exportDate: Date
    let recordings: [RecordingDTO]
    let rules: [ReplacementRuleDTO]
}

struct RecordingDTO: Codable {
    let id: UUID
    let createdAt: Date
    let duration: TimeInterval
    let transcription: String?
    let segments: [TranscriptionSegment]?
}

struct ReplacementRuleDTO: Codable {
    let id: UUID
    let textToReplace: String
    let additionalIncorrectForms: [String]
    let replacementText: String
    let createdAt: Date
    let weight: Float
    let useFuzzyMatching: Bool
}

struct ImportSummary: Equatable {
    var recordingsImported: Int = 0
    var recordingsSkipped: Int = 0
    var rulesImported: Int = 0
    var rulesSkipped: Int = 0
}

// MARK: - Backup Service

@MainActor
final class DataBackupService {
    static let shared = DataBackupService()
    
    private init() {}
    
    /// Exports all valid recordings and replacement rules to a JSON payload
    func exportData(context: ModelContext) throws -> Data {
        let recordingDescriptor = FetchDescriptor<Recording>()
        let allRecordings = try context.fetch(recordingDescriptor)
        
        // Only export recordings that have an actual transcription
        let validRecordings = allRecordings.filter { recording in
            if let text = recording.transcription, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            return false
        }
        
        let recordingDTOs = validRecordings.map { r in
            RecordingDTO(
                id: r.id,
                createdAt: r.createdAt,
                duration: r.duration,
                transcription: r.transcription,
                segments: r.segments
            )
        }
        
        let rulesDescriptor = FetchDescriptor<ReplacementRule>()
        let allRules = try context.fetch(rulesDescriptor)
        
        let ruleDTOs = allRules.map { r in
            ReplacementRuleDTO(
                id: r.id,
                textToReplace: r.textToReplace,
                additionalIncorrectForms: r.additionalIncorrectForms,
                replacementText: r.replacementText,
                createdAt: r.createdAt,
                weight: r.weight,
                useFuzzyMatching: r.useFuzzyMatching
            )
        }
        
        let payload = BackupPayload(
            version: 1,
            exportDate: Date(),
            recordings: recordingDTOs,
            rules: ruleDTOs
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        return try encoder.encode(payload)
    }
    
    /// Imports a JSON payload, skipping duplicates and persisting new models to the context
    func importData(from data: Data, context: ModelContext) throws -> ImportSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let payload = try decoder.decode(BackupPayload.self, from: data)
        var summary = ImportSummary()
        
        let existingRecordings = try context.fetch(FetchDescriptor<Recording>())
        let existingRules = try context.fetch(FetchDescriptor<ReplacementRule>())
        
        for dto in payload.recordings {
            guard let text = dto.transcription, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                summary.recordingsSkipped += 1
                continue
            }
            
            // Duplicate logic: same UUID or (same creation time within 1 second AND same text)
            let isDuplicate = existingRecordings.contains { ext in
                if ext.id == dto.id { return true }
                let timeDiff = abs(ext.createdAt.timeIntervalSince1970 - dto.createdAt.timeIntervalSince1970)
                return timeDiff < 1.0 && ext.transcription == text
            }
            
            if isDuplicate {
                summary.recordingsSkipped += 1
            } else {
                let newRec = Recording(
                    id: dto.id,
                    createdAt: dto.createdAt, // Maintain chronological order
                    duration: dto.duration,
                    transcription: text,
                    liveTranscription: nil,
                    transcriptionStatus: .completed,
                    filename: "imported_\(dto.id.uuidString).m4a", // Dummy filename since audio isn't exported
                    isFileDeleted: true, // Audio file is inherently absent
                    transcriptionEngine: "Imported",
                    segments: dto.segments
                )
                context.insert(newRec)
                summary.recordingsImported += 1
            }
        }
        
        for dto in payload.rules {
            // Duplicate logic: same UUID or case-insensitive match on target & replacement
            let isDuplicate = existingRules.contains { ext in
                ext.id == dto.id || (ext.textToReplace.lowercased() == dto.textToReplace.lowercased() && ext.replacementText.lowercased() == dto.replacementText.lowercased())
            }
            
            if isDuplicate {
                summary.rulesSkipped += 1
            } else {
                let newRule = ReplacementRule(
                    id: dto.id,
                    textToReplace: dto.textToReplace,
                    additionalIncorrectForms: dto.additionalIncorrectForms,
                    replacementText: dto.replacementText,
                    createdAt: dto.createdAt,
                    weight: dto.weight,
                    useFuzzyMatching: dto.useFuzzyMatching
                )
                context.insert(newRule)
                summary.rulesImported += 1
            }
        }
        
        try context.save()
        return summary
    }
}
