import Foundation
import CoreAudio

/// Provides CoreAudio utility functions for device management and sample rate alignment.
/// This is used to fix the Bluetooth HFP / A2DP mismatch bug where the input and output
/// devices have differing sample rates, causing `AVAudioEngine` to fail silently.
public final class CoreAudioDeviceManager: @unchecked Sendable {
    private var originalOutputSampleRate: Float64 = 0
    private var outputDeviceIDForRestore: AudioDeviceID = kAudioObjectUnknown

    public init() {}

    /// Returns the nominal sample rate of the default input device via CoreAudio.
    /// Does NOT create an `AVAudioEngine` — no hardware is captured.
    public func defaultInputSampleRate() -> Float64 {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &propSize, &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else { return 0 }

        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate = Float64(0)
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(deviceID, &rateAddr, 0, nil, &rateSize, &rate)
        return rate
    }

    /// Returns the nominal sample rate of the default output device via CoreAudio.
    public func defaultOutputSampleRate() -> Float64 {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &propSize, &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else { return 0 }

        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate = Float64(0)
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(deviceID, &rateAddr, 0, nil, &rateSize, &rate)
        return rate
    }

    /// Aligns the default output device's nominal sample rate to match the target rate (usually input).
    /// Returns `true` if alignment succeeded (or was not needed), `false` if the output device rejected it.
    @discardableResult
    public func alignOutputSampleRate(to targetRate: Float64) -> Bool {
        var outputDeviceID = AudioDeviceID(kAudioObjectUnknown)
        var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultOutputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddr, 0, nil, &propSize, &outputDeviceID
        ) == noErr, outputDeviceID != kAudioObjectUnknown else {
            Log("alignOutputSampleRate: failed to get default output device", level: .error)
            return false
        }

        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var currentRate = Float64(0)
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(outputDeviceID, &rateAddr, 0, nil, &rateSize, &currentRate)

        guard currentRate != targetRate else {
            Log("alignOutputSampleRate: already at \(targetRate)Hz — no change needed")
            originalOutputSampleRate = 0
            outputDeviceIDForRestore = kAudioObjectUnknown
            return true
        }

        Log("alignOutputSampleRate: output \(currentRate)Hz → \(targetRate)Hz (saving for restore)")
        originalOutputSampleRate = currentRate
        outputDeviceIDForRestore = outputDeviceID

        var newRate = targetRate
        let err = AudioObjectSetPropertyData(outputDeviceID, &rateAddr, 0, nil, rateSize, &newRate)
        if err != noErr {
            Log("alignOutputSampleRate: AudioObjectSetPropertyData failed with error \(err) — Bluetooth HFP device rejected rate change", level: .error)
            originalOutputSampleRate = 0
            outputDeviceIDForRestore = kAudioObjectUnknown
            return false
        }
        return true
    }

    /// Restores the output sample rate to its original value after recording completes.
    public func restoreOutputSampleRate() {
        guard outputDeviceIDForRestore != kAudioObjectUnknown, originalOutputSampleRate > 0 else { return }

        var availRatesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(0)
        let sizeErr = AudioObjectGetPropertyDataSize(outputDeviceIDForRestore, &availRatesAddr, 0, nil, &dataSize)
        if sizeErr == noErr && dataSize > 0 {
            let count = Int(dataSize) / MemoryLayout<AudioValueRange>.size
            var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
            AudioObjectGetPropertyData(outputDeviceIDForRestore, &availRatesAddr, 0, nil, &dataSize, &ranges)
            let supported = ranges.contains { range in
                originalOutputSampleRate >= range.mMinimum && originalOutputSampleRate <= range.mMaximum
            }
            if !supported {
                Log("restoreOutputSampleRate: \(originalOutputSampleRate)Hz not supported by output device (likely BT in HFP mode) — skipping restore")
                originalOutputSampleRate = 0
                outputDeviceIDForRestore = kAudioObjectUnknown
                return
            }
        }

        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate = originalOutputSampleRate
        let rateSize = UInt32(MemoryLayout<Float64>.size)
        let err = AudioObjectSetPropertyData(outputDeviceIDForRestore, &rateAddr, 0, nil, rateSize, &rate)
        if err == noErr {
            Log("restoreOutputSampleRate: restored output to \(originalOutputSampleRate)Hz")
        } else {
            Log("restoreOutputSampleRate: failed to restore: \(err)", level: .error)
        }
        originalOutputSampleRate = 0
        outputDeviceIDForRestore = kAudioObjectUnknown
    }
}
