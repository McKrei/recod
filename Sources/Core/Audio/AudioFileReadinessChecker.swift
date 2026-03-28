import AVFoundation
import Foundation

struct AudioFileReadinessResult: Sendable {
    let frameCount: AVAudioFramePosition
    let lastErrorDescription: String?
}

enum AudioFileReadinessChecker {
    private static let baseRetryDelayNanoseconds: UInt64 = 100_000_000
    private static let defaultAttempts = 12

    static func waitForReadableFrames(at url: URL, attempts: Int = defaultAttempts) async -> AudioFileReadinessResult {
        var lastErrorDescription: String?

        for attempt in 0..<attempts {
            do {
                let file = try AVAudioFile(forReading: url)
                let frameCount = file.length
                if frameCount > 0 {
                    return AudioFileReadinessResult(frameCount: frameCount, lastErrorDescription: nil)
                }
            } catch {
                lastErrorDescription = error.localizedDescription
            }

            try? await Task.sleep(nanoseconds: baseRetryDelayNanoseconds * UInt64(attempt + 1))
        }

        return AudioFileReadinessResult(frameCount: 0, lastErrorDescription: lastErrorDescription)
    }
}
