# Parakeet Background Actor — Implementation Plan

**Goal:** Вынести ONNX-инференс Parakeet с главного потока (`@MainActor`) на background,
чтобы UI не зависал при транскрибации длинных файлов.

**Date:** 2026-03-04
**Branch:** `refactor/parakeet-background-actor`

---

## Диагноз проблемы

| Сервис | Актор | Реальное поведение при `await` |
|--------|-------|-------------------------------|
| `TranscriptionService` | `@MainActor` | `kit.transcribe()` **реально уходит** на background (WhisperKit внутри диспатчит CoreML/Neural Engine на фоновые потоки). UI не зависает. |
| `ParakeetTranscriptionService` | `@MainActor` | `transcribeLongAudioInChunks` крутит синхронный ONNX-цикл с `Task.yield()` между чанками. `Task.yield()` возвращается на тот же `@MainActor` — блокировка главного потока сохраняется. **UI зависает.** |

**Корень:** `ParakeetTranscriptionService` помечен `@MainActor`, поэтому весь
ONNX-инференс (`recognizer.decode(samples:sampleRate:)`) выполняется на главном потоке.
`Task.yield()` лишь отдаёт управление другим задачам **того же актора** — UI-рендеринг
всё равно блокируется тяжёлым синхронным вычислением.

**Что НЕ является проблемой:** `TranscriptionService` менять не нужно — он уже работает
корректно. `RecordingOrchestrator` менять не нужно — он вызывает оба сервиса с `await`.

---

## Решение: `actor ParakeetTranscriptionService`

Заменить `@MainActor final class` на `actor`. Swift `actor` по умолчанию работает
на cooperative thread pool (background), а не на main thread. Изоляция свойств
(`recognizer`, `currentModelDir`) обеспечивается актором — data races исключены без
ручных блокировок. `SherpaOnnxOfflineRecognizer` (C++-обёртка) изолирован внутри
актора, поэтому проблем с `Sendable` нет.

`RecordingOrchestrator` вызывает `ParakeetTranscriptionService.shared.transcribe(...)` 
уже через `await` — после рефакторинга `await` на actor-вызов автоматически 
хопает с `@MainActor` на background, ONNX крутится в фоне, UI живёт своей жизнью.

---

## Затрагиваемые файлы

| Файл | Тип изменения |
|------|--------------|
| `Sources/Core/Services/ParakeetTranscriptionService.swift` | MODIFY: `@MainActor final class` → `actor` |

Всё остальное (`RecordingOrchestrator`, `StreamingTranscriptionService`, `TranscriptionService`,
`OverlayState`, `ClipboardService`) — **не меняется**.

---

## Task 1: Изменить объявление класса

**Файл:** `Sources/Core/Services/ParakeetTranscriptionService.swift`

**До:**
```swift
@MainActor
final class ParakeetTranscriptionService {
    static let shared = ParakeetTranscriptionService()
```

**После:**
```swift
actor ParakeetTranscriptionService {
    static let shared = ParakeetTranscriptionService()
```

Убрать `@MainActor`, убрать `final` (акторы финальны по умолчанию).

---

## Task 2: Убрать `Task.yield()` — он больше не нужен

В методе `transcribeLongAudioInChunks` (строка ~265) есть:

```swift
// Give MainActor a chance to process UI events between heavy chunks.
if index < samples.count {
    await Task.yield()
}
```

Этот комментарий и вызов были нужны только потому, что инференс шёл на `@MainActor`.
В `actor` контексте `Task.yield()` лишний — убрать вместе с комментарием.
Сам цикл по чанкам остаётся (он нужен для управления памятью, не для UI).

**До:**
```swift
index = end

// Give MainActor a chance to process UI events between heavy chunks.
if index < samples.count {
    await Task.yield()
}
```

**После:**
```swift
index = end
```

Поскольку теперь нет `await` внутри цикла, функция `transcribeLongAudioInChunks`
перестаёт быть `async`. Убрать ключевое слово `async` из её сигнатуры:

**До:**
```swift
private func transcribeLongAudioInChunks(samples: [Float], chunkSeconds: Double) async -> (String, [TranscriptionSegment]) {
```

**После:**
```swift
private func transcribeLongAudioInChunks(samples: [Float], chunkSeconds: Double) -> (String, [TranscriptionSegment]) {
```

И убрать `await` на вызовах этой функции в `transcribe(audioURL:...)` (строка ~219):

**До:**
```swift
(text, segments) = await transcribeLongAudioInChunks(samples: samples, chunkSeconds: longAudioChunkSeconds)
```

**После:**
```swift
(text, segments) = transcribeLongAudioInChunks(samples: samples, chunkSeconds: longAudioChunkSeconds)
```

---

## Task 3: Проверить вызывающие стороны

### `RecordingOrchestrator.swift`

```swift
// Строка ~404
let result = try await ParakeetTranscriptionService.shared.transcribe(audioURL: url, modelDir: modelDir, rules: rules)
```

Уже через `await` — изменений не нужно. После рефакторинга `await` автоматически
хопает с `@MainActor` RecordingOrchestrator на actor-поток Parakeet.

### `StreamingTranscriptionService.swift` (если используется)

Нужно проверить, вызывает ли `StreamingTranscriptionService` напрямую
`ParakeetTranscriptionService.shared.transcribe(audioSamples:)`. Этот метод
**синхронный** (`func transcribe(audioSamples:)` — не `async`). Внутри `actor`
синхронный метод доступен только изнутри актора или через `await` снаружи.

Если `StreamingTranscriptionService` вызывает его синхронно — нужно добавить `await`
на этот вызов или сделать вспомогательную `async` обёртку.

**Проверить при компиляции** — компилятор явно укажет на все такие места.

---

## Task 4: Сборка и верификация

```bash
make build
```

Swift 6 строгая конкурентность скажет если где-то есть проблемы с `Sendable` или
нарушение actor-изоляции. Исправить все ошибки компилятора.

```bash
make test
```

Прогнать тесты.

---

## Ожидаемые ошибки компилятора и их решения

| Ошибка | Решение |
|--------|---------|
| `actor-isolated property 'recognizer' can not be referenced from a non-isolated context` | Добавить `await` на вызов метода сервиса |
| `expression is 'async' but is not marked with 'await'` | Добавить `await` |
| `call to actor-isolated instance method '...' in a synchronous nonisolated context` | Сделать вызывающий метод `async` и добавить `await` |
| Ошибки в `StreamingTranscriptionService` при синхронном вызове `transcribe(audioSamples:)` | Добавить `await` или `async` обёртку |

---

## Что НЕ меняется

- `TranscriptionService` — и так работает корректно (WhisperKit на background)
- `RecordingOrchestrator` — уже вызывает оба сервиса через `await`
- `OverlayState`, `ClipboardService`, `PostProcessingService` — не затронуты
- Поведение приложения — идентично, только UI больше не зависает

---

## Edge Cases

| Сценарий | Поведение |
|----------|-----------|
| Два одновременных retranscribe с Parakeet | Actor сериализует вызовы автоматически — второй ждёт пока первый освободит `recognizer`. Это корректно и безопасно. |
| Streaming + batch одновременно | `StreamingTranscriptionService` и `runBatchTranscription` оба хотят `recognizer`. Actor выстроит их в очередь — data race исключён. |
| Запись `clearCache()` во время транскрибации | Actor обеспечивает взаимное исключение — `clearCache()` выполнится только когда транскрибация закончится. |
