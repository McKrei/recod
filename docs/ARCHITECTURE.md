# Архитектура Приложения

## Обзор
Recod — это нативное приложение для macOS, созданное с использованием **SwiftUI 6** и **SwiftData**. Оно следует модульному паттерну MVVM (Model-View-ViewModel), с четким разделением ответственностей и использованием современной конкурентности (`async/await`).

См. также: `docs/POST_PROCESSING.md` для LLM post-processing подсистемы.

## Структура Проекта

```
Sources/
├── App/                 # Точка входа (RecodApp.swift), AppState (конфигурация)
├── Features/            # Модули функциональности
│   ├── Settings/        # Экран настроек и его компоненты
│   ├── History/         # Логика и views истории
│   └── Overlay/         # Плавающее окно статуса записи
│       ├── OverlayState.swift  # Состояние оверлея (isVisible, status)
│       └── Components/         # Подкомпоненты (MicCore, Ripples, Loader)
├── Core/
│   ├── Orchestration/   # RecordingOrchestrator (бизнес-логика записи и транскрипции)
│   ├── Audio/           # Низкоуровневая работа со звуком
│   │   ├── AudioRecorder.swift       # Фасад для AVAudioEngine
│   │   ├── AudioLevelMonitor.swift   # Расчет громкости (RMS/vDSP)
│   │   ├── AudioStreamBuffer.swift   # Буферизация для Whisper (16kHz)
│   │   └── CoreAudioDeviceManager.swift # Фиксы Bluetooth HFP/Sample Rate
│   ├── Services/        # Сервисы (Transcription, Clipboard, Formatter, DataBackup)
│   ├── Utilities/       # Помощники (WindowAccessor, FileLogger)
│   └── Models/          # Общие модели (HotKeyShortcut, TranscriptionEngine)
├── DesignSystem/        # UI Константы (AppTheme) и Стили
└── Model/               # SwiftData Модели (Recording.swift, ReplacementRule.swift)
```

## Хранение Данных (SwiftData)
Приложение использует SwiftData для сохранения записей и правил замены текста.
- **Модели**: `Recording`, `ReplacementRule`.
- **LLM Post-Processing модели**: `PostProcessingAction`, `PostProcessedResult`, `LLMMessage`, `LLMProvider`.
- **Контейнер**: Инициализируется в `RecodApp.swift`.
- **Оркестрация**: `RecordingOrchestrator` внедряет `ModelContext` для сохранения результатов транскрипции.
- **Резервное копирование**: `DataBackupService` использует DTO (Data Transfer Objects) для экспорта/импорта истории, словаря, post-processing результатов, actions и custom providers (без API keys).
- **Реактивность**: Views используют `@Query` для автоматического обновления списков при изменении базы.

## Аудио Подсистема (Core/Audio)
Запись аудио разделена на специализированные модули для предотвращения раздувания кода (Massive View Controller/Class):

- **AudioRecorder**: Управляет графом `AVAudioEngine`. Создает и уничтожает движок на каждую сессию (критично для Bluetooth).
- **CoreAudioDeviceManager**: Использует низкоуровневое API CoreAudio для выравнивания Sample Rate между входом и выходом. Это решает проблему "молчания" AirPods в режиме HFP.
- **AudioLevelMonitor**: Вычисляет сглаженную громкость (0...1) для анимации оверлея.
- **AudioStreamBuffer**: В реальном времени конвертирует 48kHz стерео в 16kHz моно Float для WhisperKit/Parakeet.

## Бизнес-Логика (RecordingOrchestrator)
Центральный узел приложения, координирующий поток данных:
1.  **Старт**: Проверяет готовность моделей -> Инициализирует оверлей -> Запускает `AudioRecorder`.
2.  **Стриминг**: Во время записи периодически забирает сэмплы из `AudioStreamBuffer` и отправляет в `StreamingTranscriptionService`.
3.  **Стоп**: Останавливает запись -> Сохраняет WAV -> Запускает пакетную транскрипцию (`runBatchTranscription`).
4.  **Завершение**: Применяет правила замены (`TextReplacementService`) -> Вставляет текст в активное приложение (`ClipboardService`) -> Показывает успех в оверлее.

## LLM Post-Processing
- **Основные сервисы:**
  - `LLMService` — OpenAI-compatible HTTP клиент (`/models`, `/chat/completions`).
  - `PostProcessingService` — запуск авто-action и сохранение результатов в `Recording.postProcessedResults`.
  - `KeychainService` — безопасное хранение API ключей.
  - `LLMProviderStore` — хранение custom providers в `UserDefaults`.
- **Инвариант:** на текущем этапе только один `PostProcessingAction` может быть `isAutoEnabled = true`.
- **Pipeline:** transcription -> replacements -> post-processing -> clipboard insert.
- **Clipboard правило:** при успешной post-processing вставляется transformed text, иначе исходный.

## Транскрипция (Services)
- **WhisperKit**: CoreML реализация Whisper. Поддерживает Context Biasing (Word Boosting) через инъекцию токенов.
- **Parakeet**: NVIDIA модель для GPU-транскрипции.
- **TranscriptionFormatter**: Общая логика очистки спец-токенов (`<|...|>`) и нормализации текста.

## UI и Дизайн (DesignSystem / Features)
- **The Tahoe Look**: Дизайн-система на базе материалов (`.ultraThinMaterial`) и прозрачности.
- **OverlayView**: Иерархия компонентов (`MicCore`, `VoiceAura`, `RipplePulse`), управляемая через `TimelineView` для 60 FPS анимаций.
- **SettingsView**: Модульные страницы настроек с использованием `SettingsHeaderView` и `GlassRowStyle`.

## Ключевые Инварианты (НЕ НАРУШАТЬ)
1.  **Никаких God Objects**: Логика должна быть вынесена в специализированные сервисы. `AppState` только для конфигурации.
2.  **CoreAudio API для Rate Probe**: Никогда не создавайте `AVAudioEngine` только чтобы узнать Sample Rate — это захватывает микрофон.
3.  **Вставка Текста Немедленно**: Текст должен вставляться в активное приложение сразу после готовности, не дожидаясь окончания анимации "Успех".
4.  **Single Auto Action**: Одновременно допускается только один auto-enabled post-processing action.
