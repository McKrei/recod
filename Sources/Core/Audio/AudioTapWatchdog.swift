import Foundation

final class AudioTapWatchdog: Sendable {
    private let timeoutNanoseconds: UInt64
    private let pollIntervalNanoseconds: UInt64

    init(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollIntervalNanoseconds: UInt64 = 100_000_000
    ) {
        self.timeoutNanoseconds = timeoutNanoseconds
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
    }

    func waitForBuffers(bufferCount: @escaping @Sendable () async -> Int) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while await bufferCount() == 0 && DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        return await bufferCount() > 0
    }
}
