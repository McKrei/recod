import AVFoundation
import Foundation
import Testing
@testable import Recod

@Suite("RecordingFileFactory")
struct RecordingFileFactoryTests {
    @Test("makeNewRecordingURL uses recordings directory and timestamped filename")
    func makeNewRecordingURLUsesExpectedPath() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let factory = RecordingFileFactory(recordingsDirectoryProvider: { rootDirectory })
        let date = Date(timeIntervalSince1970: 1_743_170_896)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let url = try factory.makeNewRecordingURL(date: date)

        #expect(url.deletingLastPathComponent() == rootDirectory.appendingPathComponent("Recod/Recordings"))
        #expect(url.lastPathComponent == "recording-\(formatter.string(from: date)).wav")
        #expect(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))

        try? FileManager.default.removeItem(at: rootDirectory)
    }

    @Test("makeRecordingFile creates PCM file in recordings directory")
    func makeRecordingFileCreatesPCMFile() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let factory = RecordingFileFactory(recordingsDirectoryProvider: { rootDirectory })
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)
        )
        let date = Date(timeIntervalSince1970: 1_743_170_896)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let audioFile = try factory.makeRecordingFile(for: format, date: date)

        #expect(audioFile.url.lastPathComponent == "recording-\(formatter.string(from: date)).wav")
        #expect(audioFile.fileFormat.sampleRate == 48_000)
        #expect(audioFile.fileFormat.channelCount == 2)
        #expect(FileManager.default.fileExists(atPath: audioFile.url.path))

        try? FileManager.default.removeItem(at: rootDirectory)
    }
}
