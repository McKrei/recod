# Retranscribe Feature — Implementation Plan

**Goal:** Дать пользователю возможность правой кнопкой мыши на записи в истории запустить повторную транскрибацию той же модели/движка, что сейчас выбраны в настройках.

**Date:** 2026-03-04

---

## Research Findings

- Context menu уже есть в `HistoryRowView.swift:324` (`.contextMenu {}`).
- Callback-closure архитектура View: `HistoryView` передает действия через `onDelete`, `onDeleteAudioOnly` в `HistoryRowView`. Новый `onRetranscribe` встраивается по той же схеме.
- Весь pipeline транскрибации централизован в `RecordingOrchestrator`. Публичный метод `retranscribe()` переиспользует существующий `runBatchTranscription()`.
- `AppState.selectedEngine`, `AppState.whisperModelManager`, `AppState.parakeetModelManager` — единственный источник "какая модель сейчас выбрана".
- `Recording` уже имеет поля `transcription`, `liveTranscription`, `segments`, `postProcessedResults`, `transcriptionStatus`, `transcriptionEngine`.
- `RecordingSyncService.recoverInterruptedTranscriptions()` обрабатывает статусы `.transcribing` при рестарте — retranscribe-сессии автоматически восстановятся корректно.
- `PostProcessingService.runAllAutoEnabled()` уже умеет запускать auto-action — reuse без изменений.
- Тест `HistoryLogicTests` не потребует изменений.
- UI: `HistoryRowView` уже показывает `Transcribing...` при статусе `.transcribing` — специального нового состояния не нужно.

---

## Бизнес-правила (выверено с автором)

1. **Триггер:** контекстное меню строки истории, пункт "Retranscribe" — только если `!recording.isFileDeleted`.
2. **Движок:** текущий `AppState.selectedEngine` + соответствующая selected model.
3. **Старт:**
   - Очищаем `transcription`, `liveTranscription`, `segments`, `postProcessedResults` — пользователь не видит старый результат.
   - `transcriptionStatus = .transcribing`.
   - `context.save()`.
4. **Успех:**
   - Записываем новый `transcription`, `segments`, `transcriptionEngine`.
   - Запускаем `PostProcessingService.runAllAutoEnabled()` если есть авто-action.
   - `transcriptionStatus = .completed`.
   - `context.save()`.
5. **Ошибка (любая, включая модель не готова):**
   - `transcription = nil`, `segments = nil`, `postProcessedResults = nil` (уже очищены в п.3 — повторного действия не нужно).
   - `transcriptionStatus = .failed`.
   - `context.save()`.
   - Пользователь видит "Transcription failed" в строке истории (уже поддержано в `HistoryRowView`).
6. **Clipboard:** текст НЕ вставляется в буфер и НЕ пастится в активное приложение (это ретранскрибация, а не запись нового).
7. **Overlay:** НЕ показывается (это фоновая операция в строке истории, не fullscreen overlay).
8. **Параллелизм:** если запущено несколько retranscribe одновременно — каждый работает на своем `Recording`, блокировок нет.

---

## Затрагиваемые файлы

| Файл | Тип изменения |
|---|---|
| `Sources/Core/Orchestration/RecordingOrchestrator.swift` | NEW: публичный метод `retranscribe()` |
| `Sources/Features/History/HistoryView.swift` | MODIFY: добавить closure `onRetranscribe` + вызов оркестратора |
| `Sources/Features/History/Views/HistoryRowView.swift` | MODIFY: добавить пункт в `.contextMenu` + принять новый closure |

---

## Task 1: RecordingOrchestrator — метод `retranscribe()`

**Файл:** `Sources/Core/Orchestration/RecordingOrchestrator.swift`

**Контекст:**
- `whisperModelManager` и `parakeetModelManager` уже инжектированы как свойства оркестратора.
- `checkEngineReady(engine:)` и `runBatchTranscription()` уже существуют — переиспользуем напрямую.
- `modelContext` уже доступен как `self.modelContext`.

**Шаг 1: Добавить публичный метод после существующего блока `public func revealRecordings()`**

```swift
// MARK: - Retranscribe

/// Повторно транскрибирует существующую запись текущим движком.
/// Не показывает overlay, не вставляет текст в буфер.
public func retranscribe(recording: Recording) {
    guard let ctx = modelContext else {
        Task { await FileLogger.shared.log("retranscribe: modelContext not set", level: .error) }
        return
    }

    let engine = AppState.shared.selectedEngine

    guard checkEngineReady(engine: engine) else {
        Task { await FileLogger.shared.log("retranscribe: engine \(engine.displayName) not ready", level: .error) }
        // Выставляем failed сразу — модель не готова, файл не трогаем
        recording.transcription = nil
        recording.liveTranscription = nil
        recording.segments = nil
        recording.postProcessedResults = nil
        recording.transcriptionStatus = .failed
        try? ctx.save()
        return
    }

    Task {
        let url = recording.fileURL
        let filename = recording.filename

        await FileLogger.shared.log("Retranscribe start: \(filename), engine=\(engine.displayName)")

        // Очищаем старые результаты и ставим .transcribing
        recording.transcription = nil
        recording.liveTranscription = nil
        recording.segments = nil
        recording.postProcessedResults = nil
        recording.transcriptionStatus = .transcribing
        recording.transcriptionEngine = engine.rawValue
        try? ctx.save()

        // Прогоняем полный pipeline: transcription -> replacements -> post-processing
        // saveToClipboard = false: не вставляем текст в буфер
        await runBatchTranscription(
            recording: recording,
            url: url,
            context: ctx,
            engine: engine,
            saveToClipboard: false,
            parakeetStreamingFinal: nil
        )

        await FileLogger.shared.log("Retranscribe finished: \(filename)")
    }
}
```

**ВАЖНО:** Метод `runBatchTranscription` при ошибке выставляет `recording.transcriptionStatus = .failed` и делает `context.save()` — этот путь уже работает корректно (см. `RecordingOrchestrator.swift:312-317`). Поля `transcription/segments/postProcessedResults` остаются `nil` (мы их очистили до вызова), что соответствует бизнес-правилу п.5.

**Про clipboard внутри `runBatchTranscription`:** метод на строке `308` вызывает `ClipboardService.shared.insertText(textForClipboard, preserveClipboard: !saveToClipboard)`. При `saveToClipboard: false` он _всё равно_ вставит текст с сохранением буфера. Нужно ввести специальный флаг **или** вынести clipboard-вставку наружу.

**Решение для clipboard:** добавить параметр `skipClipboard: Bool = false` в `runBatchTranscription` и обернуть clipboard-вызов:

```swift
// В сигнатуре метода:
private func runBatchTranscription(
    recording: Recording,
    url: URL,
    context: ModelContext,
    engine: TranscriptionEngine,
    saveToClipboard: Bool,
    parakeetStreamingFinal: (String, [TranscriptionSegment])?,
    skipClipboard: Bool = false  // NEW
) async {
    // ...
    // Строка ~307 — обернуть проверкой:
    if !skipClipboard {
        Task {
            await ClipboardService.shared.insertText(textForClipboard, preserveClipboard: !saveToClipboard)
        }
    }
    // ...
}
```

Все существующие вызовы `runBatchTranscription` не меняются (дефолт `false` = поведение как раньше).

---

## Task 2: HistoryView — прокинуть closure onRetranscribe

**Файл:** `Sources/Features/History/HistoryView.swift`

**Шаг 1: Изменить `ForEach` для передачи нового closure:**

```swift
ForEach(recordings) { recording in
    HistoryRowView(
        recording: recording,
        audioPlayer: audioPlayer,
        onDelete: { deleteRecording(recording) },
        onDeleteAudioOnly: { deleteAudioOnly(recording) },
        onRetranscribe: { retranscribeRecording(recording) }   // NEW
    )
}
```

**Шаг 2: Добавить приватный метод `retranscribeRecording`:**

```swift
private func retranscribeRecording(_ recording: Recording) {
    RecordingOrchestrator.shared.retranscribe(recording: recording)
}
```

---

## Task 3: HistoryRowView — пункт контекстного меню

**Файл:** `Sources/Features/History/Views/HistoryRowView.swift`

**Шаг 1: Добавить новый closure в структуру view:**

```swift
struct HistoryRowView: View {
    let recording: Recording
    let audioPlayer: AudioPlayer
    let onDelete: () -> Void
    let onDeleteAudioOnly: () -> Void
    let onRetranscribe: () -> Void      // NEW
    // ...
}
```

**Шаг 2: Добавить пункт в `.contextMenu { ... }` перед деструктивным Delete:**

```swift
.contextMenu {
    // ... существующие пункты Copy Post-Processed, Copy Original ...

    if !recording.isFileDeleted {
        Button {
            onDeleteAudioOnly()
        } label: {
            Label("Delete Audio Only", systemImage: "waveform.slash")
        }

        // NEW — ставим перед "Delete Audio Only" или после, логично рядом
        Button {
            onRetranscribe()
        } label: {
            Label("Retranscribe", systemImage: "arrow.trianglehead.2.clockwise.rotate.90.circle")
        }
    }

    Button(role: .destructive, action: onDelete) {
        Label("Delete", systemImage: "trash")
    }
}
```

**Финальный порядок пунктов в меню:**
1. Copy Post-Processed _(если есть)_
2. Copy Original _(если есть транскрипция)_
3. Retranscribe _(только если `!isFileDeleted`)_
4. Delete Audio Only _(только если `!isFileDeleted`)_
5. Delete _(деструктивный, всегда)_

---

## Edge Cases

| Сценарий | Поведение |
|---|---|
| Файл уже удален (`isFileDeleted = true`) | Пункт "Retranscribe" не показывается в меню |
| Модель не загружена/не выбрана | `checkEngineReady` → `false` → сразу `.failed`, очищаем |
| Повторный Retranscribe пока идет первый | Запускается параллельно; каждый на своем `Recording` — safe |
| Запись уже в статусе `.transcribing` или `.postProcessing` | Пользователь не заблокирован UI — может нажать снова, строка просто продолжит показывать прогресс |
| Post-processing action недоступен (нет ключа API) | `PostProcessingService.runAllAutoEnabled` вернёт `nil`, `transcriptionStatus` = `.completed` с исходной транскрипцией без пост-обработки |
| Retranscribe запускается во время активной записи | Независимые операции, не конфликтуют |

---

## Тесты (что добавить)

**Файл:** `Tests/HistoryLogicTests.swift` — добавить `@Test` в существующий suite `HistoryLogicTests`.

Тесты — чисто юнит, без hardware/ML:

1. **`testRetranscribe_clearsFieldsOnStart`** — симулировать очистку полей до вызова runBatch: проверить, что `transcription == nil`, `segments == nil`, `postProcessedResults == nil`, `status == .transcribing` после очистки.
2. **`testRetranscribe_onFailure_statusIsFailed`** — симулировать ошибку (установить status = .failed, transcription = nil): проверить что поля nil и status == .failed.

> Полноценный E2E тест с реальным ML инференсом не добавляется (соответствует правилу из `docs/TESTING.md` — TranscriptionService не тестируем).

---

## Что НЕ меняется

- `Recording.swift` — новых полей не нужно.
- `OverlayView` / `OverlayState` — overlay не показывается для retranscribe.
- `ClipboardService` — только флаг `skipClipboard` экранирует вызов.
- `DataBackupService` — экспорт/импорт не меняется.
- `PostProcessingService` — reuse без изменений.
- `TranscriptionService` / `ParakeetTranscriptionService` — reuse без изменений.
- `RecordingSyncService` — already handles `.transcribing` recovery correctly.
