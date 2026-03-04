import Foundation
import Testing
@testable import Recod

@Suite("BatchTranscriptionQueue", .serialized)
@MainActor
struct BatchTranscriptionQueueTests {

    actor FakeParakeetService: BatchParakeetTranscribing {
        private var callCount = 0
        private var clearCacheCallCount = 0
        private var delayNanoseconds: UInt64 = 0
        private var errorToThrow: Error?
        private var resultToReturn: (String, [TranscriptionSegment]) = ("fake text", [])
        private var lastHotwords: [ParakeetHotword] = []

        func transcribe(audioURL: URL, modelDir: URL, hotwords: [ParakeetHotword]) async throws -> (String, [TranscriptionSegment]) {
            callCount += 1
            lastHotwords = hotwords
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            if let errorToThrow {
                throw errorToThrow
            }
            return resultToReturn
        }

        func clearCache() {
            clearCacheCallCount += 1
        }

        func setDelay(milliseconds: UInt64) {
            delayNanoseconds = milliseconds * 1_000_000
        }

        func setError(_ error: Error?) {
            errorToThrow = error
        }

        func getCallCount() -> Int {
            callCount
        }

        func getClearCacheCallCount() -> Int {
            clearCacheCallCount
        }

        func getLastHotwords() -> [ParakeetHotword] {
            lastHotwords
        }
    }

    actor FakeWhisperService: BatchWhisperTranscribing {
        private var callCount = 0
        private var clearCacheCallCount = 0
        private var lastBiasingEntries: [InferenceBiasingEntry] = []

        func transcribe(audioURL: URL, modelURL: URL, biasingEntries: [InferenceBiasingEntry]) async throws -> (String, [TranscriptionSegment]) {
            callCount += 1
            lastBiasingEntries = biasingEntries
            return ("whisper fake text", [])
        }

        func clearCache() async {
            clearCacheCallCount += 1
        }

        func getCallCount() -> Int { callCount }
        func getClearCacheCallCount() -> Int { clearCacheCallCount }
        func getLastBiasingEntries() -> [InferenceBiasingEntry] { lastBiasingEntries }
    }

    @Test("Enqueue выполняет одну задачу и вызывает clearCache")
    func singleJobExecuted() async throws {
        let fake = FakeParakeetService()
        let queue = BatchTranscriptionQueue(parakeetService: fake, whisperService: FakeWhisperService())

        var completedID: UUID?
        var completedText: String?

        await queue.setCallbacks(
            onJobCompleted: { id, text, _ in
                completedID = id
                completedText = text
            }
        )

        let id = UUID()
        await queue.enqueue(makeParakeetJob(id: id))

        try await waitUntil { completedID == id }

        #expect(completedID == id)
        #expect(completedText == "fake text")
        #expect(await fake.getCallCount() == 1)
        #expect(await fake.getClearCacheCallCount() == 1)
    }

    @Test("Задачи выполняются последовательно (FIFO)")
    func fifoOrdering() async throws {
        let fake = FakeParakeetService()
        await fake.setDelay(milliseconds: 40)
        let queue = BatchTranscriptionQueue(parakeetService: fake, whisperService: FakeWhisperService())

        var completedOrder: [UUID] = []
        await queue.setCallbacks(
            onJobCompleted: { id, _, _ in
                completedOrder.append(id)
            }
        )

        let ids = (0..<3).map { _ in UUID() }
        for id in ids {
            await queue.enqueue(makeParakeetJob(id: id))
        }

        try await waitUntil { completedOrder.count == ids.count }
        #expect(completedOrder == ids)
    }

    @Test("Дедупликация удаляет pending job с тем же recordingID")
    func deduplicatesPendingJobsByRecordingID() async throws {
        let fake = FakeParakeetService()
        await fake.setDelay(milliseconds: 120)
        let queue = BatchTranscriptionQueue(parakeetService: fake, whisperService: FakeWhisperService())

        let firstID = UUID()
        let duplicateID = UUID()

        await queue.enqueue(makeParakeetJob(id: firstID))
        await queue.enqueue(makeParakeetJob(id: duplicateID))
        await queue.enqueue(makeParakeetJob(id: duplicateID))

        try await waitUntil { await fake.getCallCount() == 2 }
        #expect(await fake.getCallCount() == 2)
    }

    @Test("Cancel удаляет pending job и вызывает callback")
    func cancelPendingJob() async throws {
        let fake = FakeParakeetService()
        await fake.setDelay(milliseconds: 150)
        let queue = BatchTranscriptionQueue(parakeetService: fake, whisperService: FakeWhisperService())

        var cancelledID: UUID?
        await queue.setCallbacks(
            onJobCancelled: { id in
                cancelledID = id
            }
        )

        let runningID = UUID()
        let pendingID = UUID()

        await queue.enqueue(makeParakeetJob(id: runningID))
        await queue.enqueue(makeParakeetJob(id: pendingID))
        await queue.cancel(recordingID: pendingID)

        try await waitUntil { cancelledID == pendingID }
        #expect(cancelledID == pendingID)
        #expect(await queue.pendingCount == 0)
    }

    @Test("clearCache вызывается даже при ошибке")
    func clearCacheCalledOnError() async throws {
        let fake = FakeParakeetService()
        await fake.setError(NSError(domain: "tests", code: -1))
        let queue = BatchTranscriptionQueue(parakeetService: fake, whisperService: FakeWhisperService())

        await queue.enqueue(makeParakeetJob(id: UUID()))

        try await waitUntil { await fake.getClearCacheCallCount() == 1 }
        #expect(await fake.getClearCacheCallCount() == 1)
    }

    @Test("Parakeet batch пробрасывает hotwords из biasing snapshot")
    func parakeetHotwordsPropagation() async throws {
        let fake = FakeParakeetService()
        let queue = BatchTranscriptionQueue(parakeetService: fake, whisperService: FakeWhisperService())

        let job = makeParakeetJob(
            id: UUID(),
            biasingEntries: [
                InferenceBiasingEntry(text: "OpenCode", weight: 2.0),
                InferenceBiasingEntry(text: "Recod", weight: 1.5)
            ]
        )
        await queue.enqueue(job)

        try await waitUntil { await fake.getCallCount() == 1 }

        let hotwords = await fake.getLastHotwords()
        #expect(hotwords.count == 2)
        #expect(hotwords[0].text == "OpenCode")
        #expect(hotwords[0].weight == 2.0)
    }

    @Test("Whisper batch использует отдельный сервис и clearCache")
    func whisperWorkerLifecycle() async throws {
        let fakeParakeet = FakeParakeetService()
        let fakeWhisper = FakeWhisperService()
        let queue = BatchTranscriptionQueue(parakeetService: fakeParakeet, whisperService: fakeWhisper)

        var completed = false
        await queue.setCallbacks(onJobCompleted: { _, _, _ in
            completed = true
        })

        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-batch.wav")
        FileManager.default.createFile(atPath: audioURL.path, contents: Data("stub".utf8))

        await queue.enqueue(
            BatchTranscriptionJob(
                recordingID: UUID(),
                audioURL: audioURL,
                engine: .whisperKit,
                enqueuedAt: Date(),
                biasingEntries: [InferenceBiasingEntry(text: "WhisperWord", weight: 3.0)],
                whisperModelURL: FileManager.default.temporaryDirectory,
                parakeetModelDir: nil
            )
        )

        try await waitUntil { completed }

        #expect(await fakeWhisper.getCallCount() == 1)
        #expect(await fakeWhisper.getClearCacheCallCount() == 1)
        #expect(await fakeWhisper.getLastBiasingEntries().first?.text == "WhisperWord")
    }

    @Test("Очередь ждёт async onJobCompleted перед следующей задачей")
    func queueWaitsForAsyncCompletionCallback() async throws {
        let fake = FakeParakeetService()
        let queue = BatchTranscriptionQueue(parakeetService: fake, whisperService: FakeWhisperService())

        let firstID = UUID()
        let secondID = UUID()

        var secondStartedBeforeFirstCallbackFinished = false
        var firstCallbackFinished = false

        await queue.setCallbacks(
            onJobStarted: { id in
                if id == secondID && !firstCallbackFinished {
                    secondStartedBeforeFirstCallbackFinished = true
                }
            },
            onJobCompleted: { id, _, _ in
                if id == firstID {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    firstCallbackFinished = true
                }
            }
        )

        await queue.enqueue(makeParakeetJob(id: firstID))
        await queue.enqueue(makeParakeetJob(id: secondID))

        try await waitUntil { await fake.getCallCount() == 2 }
        #expect(secondStartedBeforeFirstCallbackFinished == false)
    }

    private func makeParakeetJob(id: UUID, biasingEntries: [InferenceBiasingEntry] = []) -> BatchTranscriptionJob {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(id.uuidString).wav")
        if !FileManager.default.fileExists(atPath: audioURL.path) {
            FileManager.default.createFile(atPath: audioURL.path, contents: Data("stub".utf8))
        }

        return BatchTranscriptionJob(
            recordingID: id,
            audioURL: audioURL,
            engine: .parakeet,
            enqueuedAt: Date(),
            biasingEntries: biasingEntries,
            whisperModelURL: nil,
            parakeetModelDir: FileManager.default.temporaryDirectory
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollNanoseconds: UInt64 = 20_000_000,
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: pollNanoseconds)
        }

        Issue.record("Timed out while waiting for async condition")
    }
}
