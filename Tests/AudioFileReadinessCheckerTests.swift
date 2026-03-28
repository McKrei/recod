import AVFoundation
import Foundation
import Testing
@testable import Recod

@Suite("Audio File Readiness Checker")
struct AudioFileReadinessCheckerTests {
    @Test("returns frame count for readable wav file")
    func returnsFrameCountForReadableFile() async throws {
        let url = try makeTestWAV(frameCount: 1600)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await AudioFileReadinessChecker.waitForReadableFrames(at: url, attempts: 1)

        #expect(result.frameCount == 1600)
        #expect(result.lastErrorDescription == nil)
    }

    @Test("returns empty result for unreadable file")
    func returnsEmptyResultForUnreadableFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let result = await AudioFileReadinessChecker.waitForReadableFrames(at: url, attempts: 1)

        #expect(result.frameCount == 0)
        #expect(result.lastErrorDescription != nil)
    }

    private func makeTestWAV(frameCount: AVAudioFrameCount) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else {
            throw TestError.failedToCreateFormat
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw TestError.failedToCreateBuffer
        }

        buffer.frameLength = frameCount
        if let channel = buffer.floatChannelData?[0] {
            for index in 0..<Int(frameCount) {
                channel[index] = Float(index % 32) / 32.0
            }
        }

        try file.write(from: buffer)
        return url
    }
}

private enum TestError: Error {
    case failedToCreateFormat
    case failedToCreateBuffer
}
