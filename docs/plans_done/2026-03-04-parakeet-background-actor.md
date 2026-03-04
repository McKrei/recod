# Parakeet Background Actor — Implementation Plan

**Goal:** Вынести ONNX-инференс Parakeet с главного потока (`@MainActor`) на background,
чтобы UI не зависал при транскрибации длинных файлов.

**Date:** 2026-03-04
**Branch:** `refactor/parakeet-background-actor`

---

## Диагноз проблемы

При транскрибации длинного файла (≥2 мин) через Parakeet приложение полностью
зависает — нельзя нажать Start/Stop, окна не двигаются, UI не обновляется.

Причина в архитектуре: весь `ParakeetTranscriptionService` помечен `@MainActor`.
Это означает, что ONNX-инференс (`recognizer.decode(samples:sampleRate:)`) выполняется
**на главном потоке**. `Task.yield()` между чанками отдаёт управление другим задачам
*того же* `@MainActor` — главный поток всё равно заблокирован тяжёлым вычислением.

Для сравнения: `TranscriptionService` (WhisperKit) тоже помечен `@MainActor`,
но WhisperKit внутри сам диспатчит CoreML/Neural Engine на background. У Parakeet
(SherpaOnnx) такого нет — вся работа идёт синхронно в вызывающем потоке.

### Таблица: кто что делает сейчас

| Файл | Актор | Тяжёлая работа |
|------|-------|----------------|
| `TranscriptionService` | `@MainActor` | WhisperKit внутренне уходит на background — **OK** |
| `ParakeetTranscriptionService` | `@MainActor` | ONNX крутится на главном потоке — **ПРОБЛЕМА** |
| `ParakeetStreamingService` | `@MainActor` | Polling-цикл + вызов transcribe — затронут рефакторингом |
| `RecordingOrchestrator` | `@MainActor` | Вызывает оба сервиса через `await` — **не меняется** |

---

## Решение

Заменить `@MainActor final class ParakeetTranscriptionService` на `actor ParakeetTranscriptionService`.

Swift `actor` выполняет работу на cooperative thread pool (background), а не на
main thread. Изоляция свойств (`recognizer`, `currentModelDir`) гарантируется самим
актором — data races исключены без ручных блокировок.

После изменения:
- `RecordingOrchestrator` (строки 92, 404) вызывает методы через `await` — это
  уже есть, хоп с `@MainActor` на actor-поток происходит автоматически.
- `ParakeetStreamingService` вызывает `transcribe(audioSamples:)` **синхронно**
  (строки 77, 136) — это нужно исправить, добавив `await`.
- `ParakeetModelManager` вызывает `clearCache()` синхронно (строка 207) — нужно
  добавить `await`.

---

## Затрагиваемые файлы

| Файл | Тип изменения |
|------|--------------|
| `Sources/Core/Services/ParakeetTranscriptionService.swift` | Убрать `@MainActor`, сделать `actor` |
| `Sources/Core/Services/ParakeetStreamingService.swift` | Добавить `await` на два вызова `transcribe(audioSamples:)` и на `prepareModel` |
| `Sources/Core/Managers/ParakeetModelManager.swift` | Добавить `await` на вызов `clearCache()` |

`TranscriptionService`, `RecordingOrchestrator`, `OverlayState`, `ClipboardService`,
`PostProcessingService` — **не меняются**.

---

## Task 1 — `ParakeetTranscriptionService.swift`

### Шаг 1.1: Изменить объявление

**Строки 31–32. До:**
```swift
@MainActor
final class ParakeetTranscriptionService {
```

**После:**
```swift
actor ParakeetTranscriptionService {
```

- Убрать `@MainActor`.
- Убрать `final` (акторы финальны по умолчанию в Swift).
- `static let shared = ParakeetTranscriptionService()` — остаётся без изменений.

### Шаг 1.2: Убрать `Task.yield()` из цикла чанков

Этот вызов был единственной причиной существования ключевого слова `async` в
`transcribeLongAudioInChunks`. В `actor`-контексте он бессмысленен — убрать.

**Строки 261–266. До:**
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

### Шаг 1.3: Сделать `transcribeLongAudioInChunks` синхронной

Поскольку `await Task.yield()` убран, внутри функции не осталось `await`-точек.
Убрать `async` из сигнатуры.

**Строка 237. До:**
```swift
private func transcribeLongAudioInChunks(samples: [Float], chunkSeconds: Double) async -> (String, [TranscriptionSegment]) {
```

**После:**
```swift
private func transcribeLongAudioInChunks(samples: [Float], chunkSeconds: Double) -> (String, [TranscriptionSegment]) {
```

### Шаг 1.4: Убрать `await` на вызове `transcribeLongAudioInChunks`

**Строка ~219. До:**
```swift
(text, segments) = await transcribeLongAudioInChunks(samples: samples, chunkSeconds: longAudioChunkSeconds)
```

**После:**
```swift
(text, segments) = transcribeLongAudioInChunks(samples: samples, chunkSeconds: longAudioChunkSeconds)
```

### Важно: `SherpaOnnxOfflineRecognizer` не `Sendable`

`SherpaOnnxOfflineRecognizer` объявлен как `public class` без `: Sendable`
(`Packages/SherpaOnnx/Sources/SherpaOnnxSwift/SherpaOnnx.swift:727`).
Это нормально — внутри `actor` свойство `recognizer` изолировано самим актором,
доступ снаружи возможен только через `await`. Swift 6 **не требует** `Sendable`
от типов, которые хранятся как свойства актора (они защищены actor isolation).

Если компилятор всё же выдаст предупреждение/ошибку про `Sendable`, добавить
в файл (не в пакет):
```swift
// В ParakeetTranscriptionService.swift, до объявления актора:
extension SherpaOnnxOfflineRecognizer: @unchecked Sendable {}
```
`@unchecked Sendable` — безопасно, поскольку экземпляр никогда не выходит за
пределы актора.

---

## Task 2 — `ParakeetStreamingService.swift`

`ParakeetStreamingService` является `@MainActor`, но вызывает методы `actor`
`ParakeetTranscriptionService` — для этого нужны `await`.

### Шаг 2.1: `prepareModel` (строка 41)

**До:**
```swift
await ParakeetTranscriptionService.shared.prepareModel(modelDir: modelDir)
```

`prepareModel` уже `async` — `await` уже есть. После рефакторинга `actor` автоматически
обработает хоп. **Изменений не нужно.**

### Шаг 2.2: `transcribe(audioSamples:)` в polling-цикле (строка ~77)

Это **синхронный** вызов из `async`-контекста. После рефакторинга синхронный вызов
метода `actor` невозможен — компилятор выдаст ошибку.

Найти контекст вызова (строки ~70–85) и добавить `await`:

**До:**
```swift
let (chunkText, chunkSegments) = ParakeetTranscriptionService.shared.transcribe(
    audioSamples: speechSamples,
    timeOffset: timeOffset
)
```

**После:**
```swift
let (chunkText, chunkSegments) = await ParakeetTranscriptionService.shared.transcribe(
    audioSamples: speechSamples,
    timeOffset: timeOffset
)
```

Убедиться, что окружающая функция помечена `async` — это `startStreaming(...)`, которая
уже `async` (строка 23). Всё корректно.

### Шаг 2.3: `transcribe(audioSamples:)` в `flushAndCollectRemaining` (строка ~136)

Та же проблема. `flushAndCollectRemaining` — **синхронная** функция (строка 118:
`func flushAndCollectRemaining() -> (String, [TranscriptionSegment])`).

Нельзя просто добавить `await` в синхронную функцию. Нужно сделать функцию `async`:

**Строка 118. До:**
```swift
func flushAndCollectRemaining() -> (String, [TranscriptionSegment]) {
```

**После:**
```swift
func flushAndCollectRemaining() async -> (String, [TranscriptionSegment]) {
```

И добавить `await` на вызов внутри:
```swift
let (chunkText, chunkSegments) = await ParakeetTranscriptionService.shared.transcribe(
    audioSamples: speechSamples,
    timeOffset: timeOffset
)
```

### Шаг 2.4: Обновить вызывающие стороны `flushAndCollectRemaining`

После того как функция стала `async`, найти все её вызовы и добавить `await`.
Скорее всего вызывается в `RecordingOrchestrator` или `StreamingTranscriptionService`.
Компилятор укажет на все места.

---

## Task 3 — `ParakeetModelManager.swift` (строка 207)

`clearCache()` вызывается синхронно. После рефакторинга — ошибка компилятора.

Найти строку 207 и окружающий контекст. Если вызывающая функция уже `async`:

**До:**
```swift
ParakeetTranscriptionService.shared.clearCache()
```

**После:**
```swift
await ParakeetTranscriptionService.shared.clearCache()
```

Если вызывающая функция **не** `async` — обернуть в `Task`:
```swift
Task {
    await ParakeetTranscriptionService.shared.clearCache()
}
```

---

## Task 4 — Сборка и верификация

```bash
make build
```

Swift 6 strict concurrency выдаст все оставшиеся ошибки actor-изоляции.
Типичные ошибки и решения:

| Ошибка компилятора | Решение |
|--------------------|---------|
| `call to actor-isolated instance method 'X' in a synchronous nonisolated context` | Сделать вызывающую функцию `async` + добавить `await` |
| `expression is 'async' but is not marked with 'await'` | Добавить `await` |
| `sending 'X' risks causing data races` про `SherpaOnnxOfflineRecognizer` | Добавить `extension SherpaOnnxOfflineRecognizer: @unchecked Sendable {}` |
| `actor-isolated property 'recognizer' can not be referenced from a non-isolated context` | Убедиться что вызов идёт через метод актора, а не напрямую к свойству |

После чистой сборки:

```bash
make test
```

---

## Тестирование

### Что проверить вручную (нет авто-тестов для ML)

1. **Короткая запись (<2 мин) → Parakeet:**
   - Запустить запись, остановить, дождаться транскрибации.
   - UI должен отвечать во время транскрибации (можно кликать, двигать окно).
   - Результат транскрибации должен совпадать с тем, что было до рефакторинга.

2. **Длинная запись (≥2 мин) → Parakeet:**
   - Это основной сценарий, который исправляем.
   - UI должен **не зависать** в течение всей транскрибации.
   - Кнопка Start должна быть кликабельна.
   - Оверлей должен показывать `.transcribing` → `.postProcessing` → `.success`.

3. **Retranscribe → Parakeet:**
   - ПКМ на записи → Retranscribe.
   - UI не зависает, строка истории показывает `Transcribing...`.
   - После завершения — корректная транскрибация.

4. **Streaming (живая транскрибация во время записи):**
   - Начать запись, говорить.
   - Лайв-текст должен обновляться в реальном времени.
   - После остановки — финальный результат корректен.

5. **Словарь (hotwords) + Parakeet:**
   - Добавить слово в Settings → Dictionary.
   - Записать и произнести это слово.
   - Должно транскрибироваться корректно.

6. **WhisperKit — регрессия:**
   - Убедиться что WhisperKit работает как раньше (мы его не трогаем).

### Существующие авто-тесты

```bash
make test
```

Затронутые рефакторингом тесты:

| Suite | Что проверяет | Ожидание |
|-------|--------------|----------|
| `TextReplacementServiceTests` | Fuzzy matching, replacement rules | Проходит без изменений |
| `TranscriptionEngineTests` | Enum rawValues, Codable | Проходит без изменений |
| `ParakeetSegmentBuilderTests` | Сегментация токенов | Проходит без изменений |
| `AudioRecorderUnitTests` | Граф AVAudioEngine, буферы | Проходит без изменений |

> Прямых тестов для `ParakeetTranscriptionService` нет (по правилу из `docs/TESTING.md` —
> сервисы ML-инференса не тестируются юнит-тестами из-за зависимости от железа).

---

## Что НЕ меняется

- `TranscriptionService` (WhisperKit) — и так работает корректно, не трогаем.
- `RecordingOrchestrator` — уже вызывает оба сервиса через `await`, изменений нет.
- `OverlayState`, `ClipboardService`, `PostProcessingService` — не затронуты.
- `DictionaryBiasingCompiler`, `ParakeetSegmentBuilder`, `AudioUtilities` —
  plain structs без actor-аннотаций, вызываются изнутри актора — всё корректно.
- Логика транскрибации, сегментации, hotwords — не меняется совсем.
- Поведение приложения для пользователя — идентично, только UI больше не зависает.

---

## Edge Cases

| Сценарий | Поведение |
|----------|-----------|
| Два одновременных вызова transcribe (batch + streaming) | Actor сериализует их автоматически — второй ждёт пока первый освободит `recognizer`. Это безопасно и корректно. |
| `clearCache()` вызван во время транскрибации | Actor обеспечивает взаимное исключение — `clearCache()` выполнится только когда transcribe закончится. |
| Отмена Task во время транскрибации (пользователь закрыл приложение) | ONNX-вызов `recognizer.decode(...)` синхронный — не проверяет cancellation. Чанк дотранскрибируется до конца. Это приемлемо — каждый чанк ≤30 секунд аудио. |
| Streaming + batch retranscribe одновременно по одной записи | Actor выстроит в очередь, data race исключён. Результаты могут конкурировать за запись в `Recording` — но это уже существующее поведение, не новая проблема. |

---

## Структура коммитов

Рекомендуется один коммит:

```
refactor: move Parakeet ONNX inference to background via actor isolation

- Change ParakeetTranscriptionService from @MainActor final class to actor
- Remove Task.yield() workaround from chunk loop (no longer needed)
- Make transcribeLongAudioInChunks synchronous (no more async suspension points)
- Add await to ParakeetStreamingService transcribe(audioSamples:) calls
- Make flushAndCollectRemaining() async to support await on actor methods
- Add await to ParakeetModelManager.clearCache() call

Fixes UI freeze when transcribing long audio files (≥2 min) with Parakeet.
WhisperKit path is unaffected.
```
