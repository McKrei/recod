import Foundation
import SwiftData
import AVFoundation

@MainActor
public struct RecordingSyncService {
    public init() {}
    
    public func syncRecordings(modelContext: ModelContext) async {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let recordingsDir = appSupportURL.appendingPathComponent("MacAudio2/Recordings")
        
        guard let files = try? fileManager.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: [.creationDateKey]) else { return }
        
        let descriptor = FetchDescriptor<Recording>()
        guard let existingRecordings = try? modelContext.fetch(descriptor) else { return }
        let existingFilenames = Set(existingRecordings.map { $0.filename })
        
        for fileURL in files {
            let filename = fileURL.lastPathComponent
            guard filename.hasSuffix(".m4a") || filename.hasSuffix(".wav") else { continue }
            
            if !existingFilenames.contains(filename) {
                let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
                let creationDate = attributes?[.creationDate] as? Date ?? Date()
                
                let asset = AVURLAsset(url: fileURL)
                let duration = (try? await asset.load(.duration))?.seconds ?? 0
                
                let newRecording = Recording(
                    createdAt: creationDate,
                    duration: duration,
                    filename: filename
                )
                modelContext.insert(newRecording)
            }
        }
        
        try? modelContext.save()
    }
}
