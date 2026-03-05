# Post-Processing Feature — Implementation Plan

## Задача
- Добавить AI-постобработку транскриптов через OpenAI-совместимые LLM: пользовательские действия с промптами, хоткеи и автоматический запуск после записи.

## Мини-план
- Подготовить модели и расширения SwiftData (`LLMMessage`, `LLMProvider`, `PostProcessingAction`, `PostProcessedResult`, поле в `Recording`).
- Реализовать сервисы: `KeychainService` для ключей провайдеров, `LLMService` для вызовов OpenAI API, `PostProcessingService` для запуска действий.
- Обновить UI/UX: таб `PostProcessingSettingsView`, формы для действий и провайдеров, строку истории с результатами и контекстным запуском.
- Интегрировать в оркестратор, Overlay и `HotKeyManager` (авто-действия, визуальное состояние, хоткеи).

## Что сделано
- Документированы модели, сервисы и подпроцессы, чтобы архитектура проверена на совместимость с существующим стеком.
- Намечены компоненты интерфейса (ActionRow, ProviderPicker, PostProcessingResults) и их связь с историей и настройками.
- Указаны точки интеграции: `RecordingOrchestrator`, `HistoryRowView`, `OverlayState`, `HotKeyManager`.
