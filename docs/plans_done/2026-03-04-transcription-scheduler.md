# TranscriptionScheduler — Implementation Plan

**Goal:** Реализовать систему двух независимых воркеров транскрибации:
1. **Interactive worker** — для live-записи, всегда готов, не блокируется батчем.
2. **Batch worker** — для Retranscribe, выполняет задачи последовательно из очереди (FIFO).
3. После завершения batch-задачи модель **выгружается из памяти** (clearCache).

**Date:** 2026-03-04
**Branch:** `feature/transcription-scheduler` (от master)

---

## Диагноз проблемы

Сейчас `RecordingOrchestrator.retranscribe()` вызывает тот же `runBatchTranscription`,
что и интерактивная запись. Оба пути используют одни синглтоны:
- `ParakeetTranscriptionService.shared`
- `TranscriptionService.shared`

Последствия:
1. **Блокировка interactive:** Если запущена ретранскрибация часового файла (~5 мин),
   новая запись начнётся, но `runBatchTranscription` после стопа встанет в очередь
   actor'а Parakeet — пользователь ждёт.
2. **Один recognizer на всё:** `SherpaOnnxOfflineRecognizer` (Parakeet) и `WhisperKit`
   создаются в единственном экземпляре. Два concurrent вызова = гонка данных.
3. **Модель не выгружается:** После ретранскрибации модель остаётся в памяти.
   640 MB Parakeet висит постоянно.

---

## Решение: два независимых воркера

```
┌─────────────────────────────────────────────────────────────┐
│  RecordingOrchestrator  (@MainActor)                        │
│                                                              │
│  startRecording() ──────► interactiveTranscriptionWorker   │
│  stopRecording()  ──────► interactiveTranscriptionWorker   │
│                                                              │
│  retranscribe()   ──────► BatchTranscriptionQueue           │
│                                ├── job1 (записи 1)          │
│                                ├── job2 (запись 2)          │  
│                                └── job3 (запись 3)          │
│                                      ▼ (FIFO, serial)       │
│                             batchTranscriptionWorker        │
└─────────────────────────────────────────────────────────────┘
```

**Ключевые принципы:**
- `interactiveTranscriptionWorker` — обёртка над существующими
  `ParakeetTranscriptionService.shared` / `TranscriptionService.shared`.
  Используется ТОЛЬКО для interactive flow (живая запись).
- `BatchTranscriptionQueue` — actor с внутренней FIFO-очередью.
  Запускает задачи по одной через **отдельный экземпляр** сервиса транскрибации.
- После каждой batch-задачи вызывается `clearCache()` на batch-экземпляре.
- Оба воркера независимы: interactive никогда не ждёт batch.

---

## Новые файлы и изменения

| Файл | Действие |
|------|---------|
| `Sources/Core/Orchestration/BatchTranscriptionQueue.swift` | НОВЫЙ — actor с очередью |
| `Sources/Core/Models/Recording.swift` | Добавить статусы `.queued`, `.cancelled` |
| `Sources/Core/Orchestration/RecordingOrchestrator.swift` | Изменить `retranscribe()` |
| `Sources/Features/History/Views/HistoryRowView.swift` | UI для `.queued` статуса + "Cancel" |
| `Tests/BatchTranscriptionQueueTests.swift` | НОВЫЙ — тесты с fake workers |

**Не меняются:**
- `ParakeetTranscriptionService` (уже `actor`)
- `TranscriptionService` (остаётся `@MainActor`)
- `StreamingTranscriptionService`, `ParakeetStreamingService`
- `OverlayState`, `ClipboardService`, `PostProcessingService`

---

## Task 1 — Recording.TranscriptionStatus

**Файл:** `Sources/Core/Models/Recording.swift:6`

Добавить два новых статуса:

```swift
// До:
enum TranscriptionStatus: String, Codable {
    case pending
    case streamingTranscription
    case transcribing
    case postProcessing
    case completed
    case failed
}

// После:
enum TranscriptionStatus: String, Codable {
    case pending
    case streamingTranscription
    case queued             // ← НОВЫЙ: стоит в очереди ретранскрибации
    case transcribing
    case postProcessing
    case completed
    case failed
    case cancelled          // ← НОВЫЙ: задача отменена из очереди
}
```

**Почему нужен `.queued`:**
- История показывает пользователю реальный статус. Вместо "зависшего" старого
  транскрипта он видит "В очереди".
- Позволяет при краш-ресторации поднять незавершённые задачи.

---

## Task 2 — BatchTranscriptionQueue (actor)

**Файл:** `Sources/Core/Orchestration/BatchTranscriptionQueue.swift` (НОВЫЙ)

### 2.1 Структура данных

```swift
// MARK: - Job

/// Один элемент очереди ретранскрибации.
struct BatchTranscriptionJob: Sendable {
    let recordingID: UUID
    let audioURL: URL
    let engine: TranscriptionEngine
    let enqueuedAt: Date
    
    // Snapshot параметров модели на момент постановки в очередь.
    // Захватываем сразу, чтобы не зависеть от будущих изменений AppState.
    let whisperModelURL: URL?   // nil если engine == .parakeet
    let parakeetModelDir: URL?  // nil если engine == .whisperKit
    let parakeetVADPath: URL?
}
```

### 2.2 Actor

```swift
// MARK: - BatchTranscriptionQueue

/// Серийная очередь задач ретранскрибации.
/// Выполняет по одной задаче за раз. Не влияет на interactive-поток.
actor BatchTranscriptionQueue {
    static let shared = BatchTranscriptionQueue()

    // --- Состояние очереди ---
    private var pendingJobs: [BatchTranscriptionJob] = []
    private var isProcessing: Bool = false

    // --- Batch-экземпляры сервисов (изолированы от interactive) ---
    // Parakeet: создаём отдельный actor-экземпляр для batch.
    // После каждого job вызываем clearCache(), чтобы освободить RAM.
    private let batchParakeetService = ParakeetTranscriptionService()
    
    // WhisperKit (@MainActor) — не можем создать отдельный экземпляр
    // без рефакторинга TranscriptionService. Поэтому для Whisper batch
    // используем shared, но через отдельную Task.detached с низким приоритетом.
    // (см. Примечание о Whisper ниже)

    // --- Callbacks для обновления SwiftData (должны быть @MainActor) ---
    // Передаём через замыкание, чтобы не держать ссылку на ModelContext.
    var onJobStarted: (@MainActor (UUID) -> Void)?
    var onJobCompleted: (@MainActor (UUID, String, [TranscriptionSegment]) -> Void)?
    var onJobFailed: (@MainActor (UUID, Error) -> Void)?
    var onJobCancelled: (@MainActor (UUID) -> Void)?

    private init() {}

    // MARK: - Public API

    /// Добавить запись в очередь (или заменить, если уже есть незапущенная задача).
    func enqueue(_ job: BatchTranscriptionJob) {
        // Дедупликация: удалить старый pending-job с тем же recordingID
        pendingJobs.removeAll { $0.recordingID == job.recordingID }
        pendingJobs.append(job)
        
        Task { await self.processNext() }
    }

    /// Отменить задачу из очереди (только если ещё не запущена).
    func cancel(recordingID: UUID) {
        let removed = pendingJobs.contains { $0.recordingID == recordingID }
        pendingJobs.removeAll { $0.recordingID == recordingID }
        
        if removed {
            let id = recordingID
            Task { @MainActor in
                self.onJobCancelled?(id)
            }
        }
        // Примечание: отмена уже ЗАПУЩЕННОЙ задачи в данной версии не поддерживается.
        // Задача работает до конца — это упрощение для v1.
        // В v2 можно добавить CancellationToken.
    }

    /// Количество задач в очереди (не считая текущей выполняемой).
    var pendingCount: Int { pendingJobs.count }

    // MARK: - Private

    private func processNext() async {
        guard !isProcessing, !pendingJobs.isEmpty else { return }
        isProcessing = true

        let job = pendingJobs.removeFirst()

        // Уведомить UI: задача стартовала
        let jobID = job.recordingID
        await MainActor.run { [weak self] in
            self?.onJobStarted?(jobID)
        }

        do {
            let (text, segments) = try await runJob(job)
            await MainActor.run { [weak self] in
                self?.onJobCompleted?(jobID, text, segments)
            }
        } catch {
            await MainActor.run { [weak self] in
                self?.onJobFailed?(jobID, error)
            }
        }

        // КРИТИЧНО: выгрузить модель после каждой задачи
        await batchParakeetService.clearCache()

        isProcessing = false

        // Запустить следующую задачу, если есть
        if !pendingJobs.isEmpty {
            Task { await self.processNext() }
        }
    }

    private func runJob(_ job: BatchTranscriptionJob) async throws -> (String, [TranscriptionSegment]) {
        switch job.engine {
        case .parakeet:
            guard let modelDir = job.parakeetModelDir else {
                throw BatchTranscriptionError.modelNotAvailable
            }
            return try await batchParakeetService.transcribe(
                audioURL: job.audioURL,
                modelDir: modelDir
            )

        case .whisperKit:
            guard let modelURL = job.whisperModelURL else {
                throw BatchTranscriptionError.modelNotAvailable
            }
            // Whisper batch: используем shared, но с низким приоритетом Task.
            // TranscriptionService (@MainActor) кешируется — после batch clearCache не нужен,
            // т.к. WhisperKit выгружает модели через deinit.
            // ВАЖНО: WhisperKit сам диспатчит инференс на CoreML/Neural Engine background,
            // поэтому занятость @MainActor минимальна.
            return try await TranscriptionService.shared.transcribe(
                audioURL: job.audioURL,
                modelURL: modelURL
            )
        }
    }
}

// MARK: - Errors

enum BatchTranscriptionError: LocalizedError {
    case modelNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .modelNotAvailable:
            return "Transcription model is not available. Please select and download a model in Settings."
        }
    }
}
```

### Примечание о Whisper batch-экземпляре

`TranscriptionService` помечен `@MainActor` и оборачивает `WhisperKit`, который
внутри сам уходит на background (CoreML + Neural Engine). Создать два независимых
`WhisperKit`-экземпляра возможно, но требует рефакторинга `TranscriptionService`:
убрать `@MainActor` и сделать его `actor`, аналогично Parakeet.

**Решение для v1 (данный план):**
Использовать `TranscriptionService.shared` для Whisper batch. Это безопасно, потому что:
- WhisperKit не блокирует main thread (инференс на Neural Engine).
- `TranscriptionService` — `final class @MainActor`: его методы выполняются на
  главном акторе только в момент setup/logging; тяжёлая работа внутри `WhisperKit`
  уходит на background.
- В любой момент только одна задача (interactive или batch) вызывает `transcribe`.
  Благодаря `BatchTranscriptionQueue.isProcessing` и тому, что interactive вызов
  происходит через `stopRecording`, гонки исключены.

**Решение для v2 (если потребуется):**
Рефакторинг `TranscriptionService` → `actor`, создание отдельного
`batchWhisperService = TranscriptionService()`.

---

## Task 3 — Изменить RecordingOrchestrator.retranscribe()

**Файл:** `Sources/Core/Orchestration/RecordingOrchestrator.swift:424`

### До (текущий код):

```swift
public func retranscribe(recording: Recording) {
    guard let ctx = modelContext else { ... }

    let engine = AppState.shared.selectedEngine
    guard checkEngineReady(engine: engine) else { ... }

    Task {
        // ... Сбрасывает поля, затем вызывает runBatchTranscription напрямую
        await runBatchTranscription(
            recording: recording,
            url: url,
            context: ctx,
            engine: engine,
            saveToClipboard: false,
            parakeetStreamingFinal: nil,
            skipClipboard: true
        )
    }
}
```

### После (новый код):

```swift
public func retranscribe(recording: Recording) {
    guard let ctx = modelContext else {
        Task { await FileLogger.shared.log("retranscribe: modelContext not set", level: .error) }
        return
    }

    let engine = AppState.shared.selectedEngine

    // Собрать URL моделей на момент постановки задачи в очередь
    let whisperModelURL: URL?
    let parakeetModelDir: URL?
    let parakeetVADPath: URL?

    switch engine {
    case .whisperKit:
        whisperModelURL = whisperModelManager.flatMap {
            guard let id = $0.selectedModelId else { return nil }
            return $0.getModelURL(for: id)
        }
        parakeetModelDir = nil
        parakeetVADPath = nil
    case .parakeet:
        whisperModelURL = nil
        parakeetModelDir = parakeetModelManager.flatMap {
            guard let id = $0.selectedModelId else { return nil }
            return $0.getModelDirectory(for: id)
        }
        parakeetVADPath = parakeetModelManager?.getVADModelPath()
    }

    // Проверить, что модель доступна
    let modelAvailable: Bool
    switch engine {
    case .whisperKit:   modelAvailable = whisperModelURL != nil
    case .parakeet:     modelAvailable = parakeetModelDir != nil
    }

    guard modelAvailable else {
        Task { await FileLogger.shared.log("retranscribe: engine \(engine.displayName) not ready", level: .error) }
        recording.transcriptionStatus = .failed
        try? ctx.save()
        return
    }

    let job = BatchTranscriptionJob(
        recordingID: recording.id,
        audioURL: recording.fileURL,
        engine: engine,
        enqueuedAt: Date(),
        whisperModelURL: whisperModelURL,
        parakeetModelDir: parakeetModelDir,
        parakeetVADPath: parakeetVADPath
    )

    // Сбросить предыдущий результат и выставить статус .queued
    recording.transcription = nil
    recording.liveTranscription = nil
    recording.segments = nil
    recording.postProcessedResults = nil
    recording.transcriptionStatus = .queued
    recording.transcriptionEngine = engine.rawValue
    try? ctx.save()

    Task { await FileLogger.shared.log("Retranscribe enqueued: \(recording.filename), engine=\(engine.displayName)") }

    Task {
        await BatchTranscriptionQueue.shared.enqueue(job)
    }
}
```

### Подписка на события BatchTranscriptionQueue

В `init()` или `setupBindings()` оркестратора настроить callbacks:

```swift
// В RecordingOrchestrator.init() или setupBindings():
Task {
    await BatchTranscriptionQueue.shared.setCallbacks(
        onJobStarted: { [weak self] recordingID in
            self?.handleBatchJobStarted(recordingID: recordingID)
        },
        onJobCompleted: { [weak self] recordingID, text, segments in
            self?.handleBatchJobCompleted(recordingID: recordingID, text: text, segments: segments)
        },
        onJobFailed: { [weak self] recordingID, error in
            self?.handleBatchJobFailed(recordingID: recordingID, error: error)
        },
        onJobCancelled: { [weak self] recordingID in
            self?.handleBatchJobCancelled(recordingID: recordingID)
        }
    )
}
```

**Вспомогательные методы оркестратора** (все `@MainActor`):

```swift
// MARK: - Batch Queue Handlers

private func handleBatchJobStarted(recordingID: UUID) {
    guard let ctx = modelContext,
          let recording = fetchRecording(id: recordingID, context: ctx) else { return }
    recording.transcriptionStatus = .transcribing
    try? ctx.save()
    Task { await FileLogger.shared.log("Batch job started: \(recording.filename)") }
}

private func handleBatchJobCompleted(recordingID: UUID, text: String, segments: [TranscriptionSegment]) {
    guard let ctx = modelContext,
          let recording = fetchRecording(id: recordingID, context: ctx) else { return }

    let rules = (try? ctx.fetch(FetchDescriptor<ReplacementRule>())) ?? []
    let finalText = rules.isEmpty ? text : TextReplacementService.applyReplacements(text: text, rules: rules)

    recording.transcription = finalText
    recording.segments = segments
    recording.transcriptionStatus = .completed
    try? ctx.save()

    Task { await FileLogger.shared.log("Batch job completed: \(recording.filename), \(text.count) chars") }

    // Post-processing для batch: запускаем, но БЕЗ вставки в буфер
    Task {
        let actions = (try? ctx.fetch(FetchDescriptor<PostProcessingAction>())) ?? []
        let autoEnabled = actions.filter { $0.isAutoEnabled }
        if !autoEnabled.isEmpty {
            recording.transcriptionStatus = .postProcessing
            try? ctx.save()
            _ = await PostProcessingService.shared.runAllAutoEnabled(
                on: recording, context: ctx, actions: actions
            )
            recording.transcriptionStatus = .completed
            try? ctx.save()
        }
    }
}

private func handleBatchJobFailed(recordingID: UUID, error: Error) {
    guard let ctx = modelContext,
          let recording = fetchRecording(id: recordingID, context: ctx) else { return }
    recording.transcriptionStatus = .failed
    try? ctx.save()
    Task { await FileLogger.shared.log("Batch job failed: \(error.localizedDescription)", level: .error) }
}

private func handleBatchJobCancelled(recordingID: UUID) {
    guard let ctx = modelContext,
          let recording = fetchRecording(id: recordingID, context: ctx) else { return }
    recording.transcriptionStatus = .cancelled
    try? ctx.save()
    Task { await FileLogger.shared.log("Batch job cancelled: \(recording.filename)") }
}

private func fetchRecording(id: UUID, context: ModelContext) -> Recording? {
    let descriptor = FetchDescriptor<Recording>(
        predicate: #Predicate { $0.id == id }
    )
    return try? context.fetch(descriptor).first
}
```

### Публичный метод отмены

```swift
// В RecordingOrchestrator:
public func cancelRetranscribe(recording: Recording) {
    let id = recording.id
    Task {
        await BatchTranscriptionQueue.shared.cancel(recordingID: id)
    }
}
```

---

## Task 4 — UI: отображение статусов `.queued` и `.cancelled`

**Файл:** `Sources/Features/History/Views/HistoryRowView.swift`

### 4.1 Добавить case в switch

В `switch recording.transcriptionStatus ?? .completed`:

```swift
case .queued:
    HStack(spacing: 8) {
        Image(systemName: "clock.arrow.2.circlepath")
            .foregroundStyle(.secondary)
        Text("Queued for retranscription")
            .foregroundStyle(.secondary)
        
        Spacer()
        
        // Кнопка отмены
        Button {
            RecordingOrchestrator.shared.cancelRetranscribe(recording: recording)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Cancel")
    }

case .cancelled:
    HStack(spacing: 4) {
        Image(systemName: "slash.circle")
            .foregroundStyle(.secondary)
        Text("Retranscription cancelled")
            .foregroundStyle(.secondary)
    }
```

### 4.2 Контекстное меню

Добавить к existing `contextMenu`:

```swift
// Показывать "Cancel Retranscription" только если в очереди
if recording.transcriptionStatus == .queued {
    Button(role: .destructive) {
        RecordingOrchestrator.shared.cancelRetranscribe(recording: recording)
    } label: {
        Label("Cancel Retranscription", systemImage: "xmark.circle")
    }
}
```

---

## Task 5 — Выгрузка модели после batch-задачи

Это уже встроено в `BatchTranscriptionQueue.processNext()`:

```swift
// После каждой задачи (успех или ошибка):
await batchParakeetService.clearCache()
```

`clearCache()` — синхронный метод `actor ParakeetTranscriptionService`:

```swift
func clearCache() {
    recognizer = nil      // SherpaOnnxOfflineRecognizer освобождается
    currentModelDir = nil
}
```

При `recognizer = nil` ARC освобождает объект `SherpaOnnxOfflineRecognizer`.
ONNX Runtime освобождает память (~640 MB). Это происходит немедленно после вызова,
поскольку `recognizer` — единственный strong reference.

**WhisperKit:** `TranscriptionService.shared` кешируется для interactive.
Для batch Whisper очищать кеш не нужно, т.к. WhisperKit хранит модель в CoreML
cache — повторная загрузка быстрая. Однако если в будущем памяти не хватает,
можно добавить `TranscriptionService.shared.clearCache()` после Whisper batch-задачи.

---

## Task 6 — Тесты (TDD подход)

**Файл:** `Tests/BatchTranscriptionQueueTests.swift` (НОВЫЙ)

Тесты используют протокол-подмену для изоляции от реального ML.

### 6.1 Fake Worker

```swift
// В тестах — fake реализация, имитирующая задержку и результат

// Нет смысла делать полноценный mock actor TranscriptionService.
// Вместо этого тестируем BatchTranscriptionQueue через его onJobCompleted callback.

// Тест-версия job с инъекцией результата:
// Расширить BatchTranscriptionJob полем `_testResult` для тестов.
// ИЛИ сделать BatchTranscriptionQueue generic/протокольным.
```

**Рекомендованный подход — Protocol Injection:**

```swift
// Добавить протокол в BatchTranscriptionQueue.swift:
protocol BatchTranscribable: Sendable {
    func transcribe(audioURL: URL, modelDir: URL) async throws -> (String, [TranscriptionSegment])
    func clearCache() async
}

// ParakeetTranscriptionService уже actor, добавить соответствие:
extension ParakeetTranscriptionService: BatchTranscribable {}

// BatchTranscriptionQueue принимает через инициализатор:
actor BatchTranscriptionQueue {
    static let shared = BatchTranscriptionQueue()
    
    private let batchParakeetService: any BatchTranscribable
    
    init(parakeetService: any BatchTranscribable = ParakeetTranscriptionService()) {
        self.batchParakeetService = parakeetService
    }
}
```

### 6.2 Тестовые сценарии

```swift
import Testing
import Foundation

@Suite("BatchTranscriptionQueue", .serialized)
@MainActor
struct BatchTranscriptionQueueTests {

    // MARK: - Fake Service

    actor FakeParakeetService: BatchTranscribable {
        var callCount = 0
        var clearCacheCallCount = 0
        var delay: TimeInterval = 0
        var resultToReturn = ("fake text", [TranscriptionSegment]())
        var errorToThrow: Error? = nil

        func transcribe(audioURL: URL, modelDir: URL) async throws -> (String, [TranscriptionSegment]) {
            callCount += 1
            if delay > 0 {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            if let error = errorToThrow { throw error }
            return resultToReturn
        }

        func clearCache() async {
            clearCacheCallCount += 1
        }
    }

    // MARK: - Tests

    @Test("Enqueue выполняет одну задачу и вызывает clearCache")
    func testSingleJobExecuted() async throws {
        let fake = FakeParakeetService()
        let queue = BatchTranscriptionQueue(parakeetService: fake)

        var completedID: UUID?
        var completedText: String?

        await queue.setCallbacks(
            onJobCompleted: { id, text, _ in
                completedID = id
                completedText = text
            }
        )

        let id = UUID()
        let job = BatchTranscriptionJob(
            recordingID: id,
            audioURL: URL(fileURLWithPath: "/tmp/fake.wav"),
            engine: .parakeet,
            enqueuedAt: Date(),
            whisperModelURL: nil,
            parakeetModelDir: URL(fileURLWithPath: "/tmp/model"),
            parakeetVADPath: nil
        )

        await queue.enqueue(job)

        // Дать время выполниться
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(completedID == id)
        #expect(completedText == "fake text")
        #expect(await fake.callCount == 1)
        #expect(await fake.clearCacheCallCount == 1) // модель выгружена!
    }

    @Test("Задачи выполняются последовательно (FIFO)")
    func testFIFOOrdering() async throws {
        let fake = FakeParakeetService()
        await fake.setDelay(0.05) // 50ms per job
        let queue = BatchTranscriptionQueue(parakeetService: fake)

        var order: [UUID] = []
        await queue.setCallbacks(
            onJobCompleted: { id, _, _ in order.append(id) }
        )

        let ids = (0..<3).map { _ in UUID() }
        for id in ids {
            let job = BatchTranscriptionJob(
                recordingID: id,
                audioURL: URL(fileURLWithPath: "/tmp/\(id).wav"),
                engine: .parakeet,
                enqueuedAt: Date(),
                whisperModelURL: nil,
                parakeetModelDir: URL(fileURLWithPath: "/tmp/model"),
                parakeetVADPath: nil
            )
            await queue.enqueue(job)
        }

        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(order == ids)
    }

    @Test("Дедупликация: повторный enqueue одного recordingID заменяет pending")
    func testDeduplication() async throws {
        let fake = FakeParakeetService()
        await fake.setDelay(0.1)
        let queue = BatchTranscriptionQueue(parakeetService: fake)

        var completedIDs: [UUID] = []
        await queue.setCallbacks(
            onJobCompleted: { id, _, _ in completedIDs.append(id) }
        )

        let sameID = UUID()
        // Добавить первую задачу (сразу начнёт выполняться)
        await queue.enqueue(makeParakeetJob(id: sameID))
        // Добавить вторую задачу с другим ID
        let otherID = UUID()
        await queue.enqueue(makeParakeetJob(id: otherID))
        // Снова добавить задачу с sameID — должна заменить otherID в pending
        await queue.enqueue(makeParakeetJob(id: sameID))

        try await Task.sleep(nanoseconds: 400_000_000)
        // sameID должен выполниться дважды (один раз уже стартовал), otherID — 0 раз
        #expect(await fake.callCount == 2)
        #expect(!completedIDs.contains(otherID))
    }

    @Test("cancel удаляет pending задачу и вызывает onJobCancelled")
    func testCancel() async throws {
        let fake = FakeParakeetService()
        await fake.setDelay(0.2) // долгая первая задача
        let queue = BatchTranscriptionQueue(parakeetService: fake)

        var cancelledID: UUID?
        await queue.setCallbacks(
            onJobCancelled: { id in cancelledID = id }
        )

        let firstID = UUID()
        let secondID = UUID()

        await queue.enqueue(makeParakeetJob(id: firstID)) // стартует сразу
        await queue.enqueue(makeParakeetJob(id: secondID)) // попадёт в pending

        // Отменить вторую задачу
        await queue.cancel(recordingID: secondID)

        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(cancelledID == secondID)
        #expect(await queue.pendingCount == 0)
    }

    @Test("clearCache вызывается даже при ошибке транскрибации")
    func testClearCacheOnError() async throws {
        let fake = FakeParakeetService()
        await fake.setError(NSError(domain: "test", code: -1))
        let queue = BatchTranscriptionQueue(parakeetService: fake)

        await queue.enqueue(makeParakeetJob(id: UUID()))
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(await fake.clearCacheCallCount == 1)
    }

    // MARK: - Helpers

    private func makeParakeetJob(id: UUID) -> BatchTranscriptionJob {
        BatchTranscriptionJob(
            recordingID: id,
            audioURL: URL(fileURLWithPath: "/tmp/\(id).wav"),
            engine: .parakeet,
            enqueuedAt: Date(),
            whisperModelURL: nil,
            parakeetModelDir: URL(fileURLWithPath: "/tmp/model"),
            parakeetVADPath: nil
        )
    }
}
```

---

## Task 7 — Crash Recovery (опционально, v1.1)

При запуске приложения поднять записи с `.queued` или `.transcribing` статусом
и переставить их обратно в очередь (если файл доступен).

```swift
// В AppState.init() или после установки modelContext:
func recoverPendingTranscriptions() {
    guard let ctx = modelContext else { return }
    
    let descriptor = FetchDescriptor<Recording>(
        predicate: #Predicate {
            $0.transcriptionStatus == .queued || $0.transcriptionStatus == .transcribing
        }
    )
    
    let stuckRecordings = (try? ctx.fetch(descriptor)) ?? []
    
    for recording in stuckRecordings {
        // Сбросить в .queued и переподать
        recording.transcriptionStatus = .queued
        try? ctx.save()
        
        RecordingOrchestrator.shared.retranscribe(recording: recording)
        Task { await FileLogger.shared.log("Crash recovery: re-queued \(recording.filename)") }
    }
}
```

---

## Архитектурная диаграмма (финальное состояние)

```
┌────────────────────────────────────────────────────────────────┐
│  AppState (@MainActor)                                          │
│  RecordingOrchestrator (@MainActor)                             │
│                                                                  │
│  startRecording() ──► preloadEngine()                           │
│  stopRecording()  ──► processFinalRecording()                   │
│                             │                                    │
│                             ▼                                    │
│                    runBatchTranscription()                       │
│                    (INTERACTIVE PATH — без изменений)           │
│                    Uses: TranscriptionService.shared            │
│                          ParakeetTranscriptionService.shared    │
│                    Shows: OverlayState                          │
│                    Inserts: ClipboardService                    │
│                                                                  │
│  retranscribe() ──► BatchTranscriptionQueue.shared.enqueue()    │
│                          │                                       │
│                          ▼  (actor, serial FIFO)                │
│                    BatchTranscriptionQueue                       │
│                    Uses: batchParakeetService (отдельный actor) │
│                          TranscriptionService.shared (Whisper)  │
│                    NO: OverlayState, ClipboardService           │
│                    After each job: clearCache()                  │
│                    Callbacks: → @MainActor RecordingOrchestrator│
│                                  → обновляет SwiftData          │
└────────────────────────────────────────────────────────────────┘
```

---

## Edge Cases и Known Issues

### 1. Паракит занят interactive flow, пришёл batch
**Сценарий:** Пользователь остановил запись — идёт `runBatchTranscription` через
`ParakeetTranscriptionService.shared`. Одновременно из очереди стартует batch-задача
через `batchParakeetService` (отдельный actor-экземпляр).

**Результат:** Два независимых экземпляра Parakeet работают параллельно.
RAM: 640 MB × 2 = ~1.28 GB. Это допустимо на современных Mac (16+ GB).
После завершения batch — `batchParakeetService.clearCache()` освобождает 640 MB.

### 2. Пользователь меняет модель в настройках во время batch
**Проблема:** Задача в очереди сохраняет `parakeetModelDir` на момент постановки.
Если пользователь удалил эту модель — задача упадёт с `modelDirectoryMissing`.

**Обработка:** `handleBatchJobFailed` выставит `recording.transcriptionStatus = .failed`.
Пользователь увидит "Transcription failed" в истории и может повторить.

### 3. Файл записи удалён до выполнения batch-задачи
**Проверка:** `recording.isFileDeleted` или `FileManager.fileExists(atPath:)`.
В `BatchTranscriptionQueue.runJob()` добавить guard:

```swift
guard FileManager.default.fileExists(atPath: job.audioURL.path) else {
    throw BatchTranscriptionError.audioFileNotFound
}
```

### 4. Swift 6 Strict Concurrency
- `BatchTranscriptionJob` — `struct`, все поля `Sendable` — OK.
- `BatchTranscriptionQueue` — `actor` — изоляция обеспечена.
- Callbacks `onJobCompleted` etc. — `@MainActor` замыкания. При присвоении
  из actor context нужен `@Sendable`:
  ```swift
  var onJobCompleted: (@Sendable @MainActor (UUID, String, [TranscriptionSegment]) -> Void)?
  ```
- `FakeParakeetService` в тестах — `actor` — OK.

### 5. Bluetooth HFP во время batch
Batch-задачи не используют `AVAudioEngine`, только читают готовый WAV файл.
Bluetooth HFP не влияет на batch-транскрибацию.

---

## Порядок имплементации (рекомендуемый)

1. **Recording.swift** — добавить `.queued` и `.cancelled` (5 мин)
2. **BatchTranscriptionQueue.swift** — создать новый файл (1–2 ч)
3. **Tests** — написать и запустить тесты с fake workers (1 ч)
4. **RecordingOrchestrator** — изменить `retranscribe()`, добавить callbacks (1 ч)
5. **HistoryRowView** — добавить UI для новых статусов (30 мин)
6. **Smoke test** вручную: запись + ретранскрибация + ещё запись (15 мин)

**Итого:** ~5–6 часов разработки.

---

## Проверочный чеклист

- [ ] `make test` проходит без ошибок
- [ ] Interactive запись работает пока идёт batch ретранскрибация
- [ ] После завершения batch-задачи Parakeet `clearCache()` вызван (проверить через логи)
- [ ] Статус записи меняется: `queued` → `transcribing` → `completed` (или `failed`)
- [ ] Кнопка Cancel в UI отменяет pending-задачи
- [ ] При добавлении повторной ретранскрибации той же записи старая pending заменяется
- [ ] Swift 6 режим: нет предупреждений о concurrency
