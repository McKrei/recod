@preconcurrency import AVFoundation
import AppKit
import Foundation

final class RecordingFileFactory: @unchecked Sendable {
    private let fileManager: FileManager
    private let recordingsDirectoryProvider: (() -> URL?)?

    init(
        fileManager: FileManager = .default,
        recordingsDirectoryProvider: (() -> URL?)? = nil
    ) {
        self.fileManager = fileManager
        self.recordingsDirectoryProvider = recordingsDirectoryProvider
    }

    func makeRecordingFile(for format: AVAudioFormat, date: Date = Date()) throws -> AVAudioFile {
        let fileURL = try makeNewRecordingURL(date: date)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        return try AVAudioFile(forWriting: fileURL, settings: settings)
    }

    func makeNewRecordingURL(date: Date = Date()) throws -> URL {
        let recordingsDirectory = try recordingsDirectoryURL()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return recordingsDirectory.appendingPathComponent("recording-\(formatter.string(from: date)).wav")
    }

    @MainActor
    func revealRecordingsInFinder() {
        guard let recordingsDirectory = try? recordingsDirectoryURL() else {
            return
        }

        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: recordingsDirectory.path)
    }

    func recordingsDirectoryURL() throws -> URL {
        let baseDirectory = recordingsDirectoryProvider?() ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let appSupportURL = baseDirectory else {
            throw RecordingFileFactoryError.applicationSupportDirectoryUnavailable
        }

        let recordingsDirectory = appSupportURL.appendingPathComponent("Recod/Recordings")
        try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        return recordingsDirectory
    }
}

enum RecordingFileFactoryError: Error {
    case applicationSupportDirectoryUnavailable
}
