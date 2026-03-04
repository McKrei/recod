import Foundation

// MARK: - Job

struct BatchTranscriptionJob: Sendable {
    let recordingID: UUID
    let audioURL: URL
    let engine: TranscriptionEngine
    let enqueuedAt: Date
    let biasingEntries: [InferenceBiasingEntry]
    let whisperModelURL: URL?
    let parakeetModelDir: URL?
}

// MARK: - Protocols

protocol BatchParakeetTranscribing: Actor {
    func transcribe(audioURL: URL, modelDir: URL, hotwords: [ParakeetHotword]) async throws -> (String, [TranscriptionSegment])
    func clearCache()
}

extension ParakeetTranscriptionService: BatchParakeetTranscribing {}

protocol BatchWhisperTranscribing: Actor {
    func transcribe(audioURL: URL, modelURL: URL, biasingEntries: [InferenceBiasingEntry]) async throws -> (String, [TranscriptionSegment])
    func clearCache() async
}

actor BatchWhisperWorker: BatchWhisperTranscribing {
    private var service: TranscriptionService?

    func transcribe(audioURL: URL, modelURL: URL, biasingEntries: [InferenceBiasingEntry]) async throws -> (String, [TranscriptionSegment]) {
        let service = await getOrCreateService()
        return try await service.transcribe(audioURL: audioURL, modelURL: modelURL, biasingEntries: biasingEntries)
    }

    func clearCache() async {
        let service = await getOrCreateService()
        await service.clearCache()
    }

    private func getOrCreateService() async -> TranscriptionService {
        if let service {
            return service
        }

        let created = await MainActor.run { TranscriptionService() }
        service = created
        return created
    }
}

// MARK: - Errors

enum BatchTranscriptionError: LocalizedError {
    case modelNotAvailable
    case audioFileNotFound

    var errorDescription: String? {
        switch self {
        case .modelNotAvailable:
            return "Transcription model is not available. Please select and download a model in Settings."
        case .audioFileNotFound:
            return "Audio file not found for this recording."
        }
    }
}

// MARK: - Queue

actor BatchTranscriptionQueue {
    typealias JobStartedCallback = @Sendable @MainActor (UUID) async -> Void
    typealias JobCompletedCallback = @Sendable @MainActor (UUID, String, [TranscriptionSegment]) async -> Void
    typealias JobFailedCallback = @Sendable @MainActor (UUID, Error) async -> Void
    typealias JobCancelledCallback = @Sendable @MainActor (UUID) async -> Void

    static let shared = BatchTranscriptionQueue()

    private var pendingJobs: [BatchTranscriptionJob] = []
    private var isProcessing = false
    private let batchParakeetService: any BatchParakeetTranscribing
    private let batchWhisperService: any BatchWhisperTranscribing

    private var onJobStarted: JobStartedCallback?
    private var onJobCompleted: JobCompletedCallback?
    private var onJobFailed: JobFailedCallback?
    private var onJobCancelled: JobCancelledCallback?

    init(
        parakeetService: any BatchParakeetTranscribing = ParakeetTranscriptionService(),
        whisperService: any BatchWhisperTranscribing = BatchWhisperWorker()
    ) {
        self.batchParakeetService = parakeetService
        self.batchWhisperService = whisperService
    }

    func setCallbacks(
        onJobStarted: JobStartedCallback? = nil,
        onJobCompleted: JobCompletedCallback? = nil,
        onJobFailed: JobFailedCallback? = nil,
        onJobCancelled: JobCancelledCallback? = nil
    ) {
        self.onJobStarted = onJobStarted
        self.onJobCompleted = onJobCompleted
        self.onJobFailed = onJobFailed
        self.onJobCancelled = onJobCancelled
    }

    func enqueue(_ job: BatchTranscriptionJob) {
        pendingJobs.removeAll { $0.recordingID == job.recordingID }
        pendingJobs.append(job)

        Task {
            await processNext()
        }
    }

    func cancel(recordingID: UUID) async {
        let removed = pendingJobs.contains { $0.recordingID == recordingID }
        pendingJobs.removeAll { $0.recordingID == recordingID }

        guard removed else { return }
        if let callback = onJobCancelled {
            await callback(recordingID)
        }
    }

    var pendingCount: Int {
        pendingJobs.count
    }

    private func processNext() async {
        guard !isProcessing, !pendingJobs.isEmpty else { return }
        isProcessing = true

        let job = pendingJobs.removeFirst()
        let jobID = job.recordingID

        if let callback = onJobStarted {
            await callback(jobID)
        }

        do {
            let (text, segments) = try await runJob(job)
            if let callback = onJobCompleted {
                await callback(jobID, text, segments)
            }
        } catch {
            if let callback = onJobFailed {
                await callback(jobID, error)
            }
        }

        switch job.engine {
        case .parakeet:
            await batchParakeetService.clearCache()
        case .whisperKit:
            await batchWhisperService.clearCache()
        }
        isProcessing = false

        if !pendingJobs.isEmpty {
            Task {
                await processNext()
            }
        }
    }

    private func runJob(_ job: BatchTranscriptionJob) async throws -> (String, [TranscriptionSegment]) {
        guard FileManager.default.fileExists(atPath: job.audioURL.path) else {
            throw BatchTranscriptionError.audioFileNotFound
        }

        switch job.engine {
        case .parakeet:
            guard let modelDir = job.parakeetModelDir else {
                throw BatchTranscriptionError.modelNotAvailable
            }
            let hotwords = job.biasingEntries.map { entry in
                ParakeetHotword(text: entry.text, weight: entry.weight)
            }
            return try await batchParakeetService.transcribe(audioURL: job.audioURL, modelDir: modelDir, hotwords: hotwords)

        case .whisperKit:
            guard let modelURL = job.whisperModelURL else {
                throw BatchTranscriptionError.modelNotAvailable
            }
            return try await batchWhisperService.transcribe(audioURL: job.audioURL, modelURL: modelURL, biasingEntries: job.biasingEntries)
        }
    }
}
