import Foundation
import AVFoundation
import Accelerate

/// Computes a smoothed 0...1 audio level from PCM buffers for UI metering.
public final class AudioLevelMonitor: @unchecked Sendable {
    private enum Config {
        static let floorDB: Float = -52
        static let ceilingDB: Float = 0
        static let attack: Float = 0.42
        static let release: Float = 0.14
        static let minimumVisibleLevel: Float = 0.01
        static let silenceRMS: Float = 0.00002
        static let epsilonRMS: Float = 0.000001
        static let shapingPower: Float = 1.18
        static let publishIntervalNanoseconds: UInt64 = 50_000_000
    }

    private let queue = DispatchQueue(label: "com.recod.audioLevelMonitorQueue")
    private var latestRawLevel: Float = 0
    private var smoothedLevel: Float = 0
    private var publisherTask: Task<Void, Never>?

    /// Callback fired on the main thread when a new level is computed.
    public var onLevelUpdate: (@MainActor (Float) -> Void)?

    public init() {}

    /// Process a new buffer to calculate the raw RMS level.
    public func processBuffer(_ buffer: AVAudioPCMBuffer) {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, let channelData = buffer.floatChannelData else { return }

        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return }

        // Fast path: compute RMS for channel 0
        var channelZeroRMS: Float = 0
        vDSP_rmsqv(channelData[0], 1, &channelZeroRMS, vDSP_Length(frameLength))

        let rms: Float
        if channelZeroRMS > Config.silenceRMS || channelCount == 1 {
            rms = channelZeroRMS
        } else {
            // Slower path: average across all channels if channel 0 is suspiciously silent
            var sum: Float = 0
            for channel in 0 ..< channelCount {
                var value: Float = 0
                vDSP_rmsqv(channelData[channel], 1, &value, vDSP_Length(frameLength))
                sum += value
            }
            rms = sum / Float(channelCount)
        }

        let safeRMS = max(rms, Config.epsilonRMS)
        let db = 20 * log10f(safeRMS)
        let clampedDB = min(max(db, Config.floorDB), Config.ceilingDB)
        let normalized = (clampedDB - Config.floorDB) / (Config.ceilingDB - Config.floorDB)
        let shaped = powf(min(max(normalized, 0), 1), Config.shapingPower)

        queue.async { [weak self] in
            self?.latestRawLevel = shaped
        }
    }

    /// Starts the publisher task which applies smoothing and calls the update callback.
    public func startPublishing() {
        stopPublishing(resetToZero: false)

        queue.sync {
            self.latestRawLevel = 0
            self.smoothedLevel = 0
        }

        publisherTask = Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                let publishedValue = self.queue.sync { () -> Float in
                    let target = self.latestRawLevel
                    let coefficient = target > self.smoothedLevel ? Config.attack : Config.release
                    self.smoothedLevel += (target - self.smoothedLevel) * coefficient
                    let clamped = min(max(self.smoothedLevel, 0), 1)
                    return clamped < Config.minimumVisibleLevel ? 0 : clamped
                }

                if let callback = self.onLevelUpdate {
                    await MainActor.run {
                        callback(publishedValue)
                    }
                }

                try? await Task.sleep(nanoseconds: Config.publishIntervalNanoseconds)
            }
        }
    }

    /// Stops publishing and optionally resets the reported level to zero.
    public func stopPublishing(resetToZero: Bool) {
        publisherTask?.cancel()
        publisherTask = nil

        queue.sync {
            self.latestRawLevel = 0
            self.smoothedLevel = 0
        }

        if resetToZero {
            if let callback = onLevelUpdate {
                Task { @MainActor in
                    callback(0)
                }
            }
        }
    }
}
