# Transcription Scheduler — Implemented

**Date:** 2026-03-04  
**Branch:** `feature/transcription-scheduler`

## Что реализовано

1. Добавлен отдельный batch scheduler для retrancribe:
   - `Sources/Core/Orchestration/BatchTranscriptionQueue.swift`
   - Actor-очередь (FIFO), одна задача за раз.
   - Дедупликация pending-задач по `recordingID`.
   - Отмена pending-задач через `cancel(recordingID:)`.

2. Обновлены статусы транскрибации:
   - `Recording.TranscriptionStatus.queued`
   - `Recording.TranscriptionStatus.cancelled`

3. `RecordingOrchestrator.retranscribe()` переведен на очередь:
   - Создает `BatchTranscriptionJob` со snapshot параметров модели.
   - Добавляет snapshot user dictionary (`InferenceBiasingEntry`) для batch inference biasing.
   - Очищает прошлый результат записи и ставит `.queued`.
   - Регистрирует callbacks очереди для переходов статусов и сохранения в SwiftData.
   - Добавлен публичный `cancelRetranscribe(recording:)`.
   - Для Parakeet batch readiness больше не зависит от VAD (VAD нужен только для streaming).

4. UI в истории обновлен:
   - `HistoryRowView` показывает `.queued` и `.cancelled`.
   - Для `.queued` добавлена кнопка `Cancel` в строке.
   - В context menu добавлен пункт `Cancel Retranscription` для queued-записей.

5. Освобождение памяти моделей после batch-задачи:
   - Для Parakeet и Whisper используются отдельные batch workers.
   - После каждого job вызывается `clearCache()` у соответствующего worker.

6. Сериализация полного pipeline в очереди:
   - Callback завершения job сделан async.
   - Следующая задача стартует только после завершения replacements + post-processing текущей.

7. Тесты:
   - Новый файл `Tests/BatchTranscriptionQueueTests.swift`.
   - Добавлены сценарии на propagation hotwords/biasing и ожидание async completion callback.
   - Обновлен `Tests/TranscriptionSegmentTests.swift` для новых enum-кейсов.

## Поведение (v1)

- Interactive запись и batch retrancribe больше не делят один execution path.
- Batch задачи выполняются последовательно и не вставляют текст в clipboard.
- Batch path сохраняет inference biasing (Whisper prompt tokens + Parakeet hotwords).
- Отмена поддерживается только для pending-задач (не для уже запущенной).

## Проверка

- `swift test --filter BatchTranscriptionQueueTests` — green.
- `make test` — инфраструктурно может флакать на аудио-хардварных тестах (`AudioEngineGraphTests`) при неподходящем input/output device state; к scheduler-изменениям не относится.
