import Foundation
import Testing
@testable import Recod

@Suite("AudioTapWatchdog")
struct AudioTapWatchdogTests {
    @Test("waitForBuffers returns true when buffers arrive before timeout")
    func waitForBuffersSucceedsBeforeTimeout() async {
        let watchdog = AudioTapWatchdog(timeoutNanoseconds: 300_000_000, pollIntervalNanoseconds: 20_000_000)
        let counter = Counter()

        Task {
            try? await Task.sleep(nanoseconds: 60_000_000)
            await counter.set(3)
        }

        let receivedBuffers = await watchdog.waitForBuffers {
            await counter.value
        }

        #expect(receivedBuffers)
    }

    @Test("waitForBuffers returns false when timeout expires")
    func waitForBuffersTimesOut() async {
        let watchdog = AudioTapWatchdog(timeoutNanoseconds: 80_000_000, pollIntervalNanoseconds: 20_000_000)

        let receivedBuffers = await watchdog.waitForBuffers {
            0
        }

        #expect(!receivedBuffers)
    }
}

private actor Counter {
    private var storage = 0

    var value: Int {
        get { storage }
    }

    func set(_ value: Int) {
        storage = value
    }
}
