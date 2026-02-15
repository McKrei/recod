# Архитектура Приложения

## Обзор
Recod — это нативное приложение для macOS, созданное с использованием **SwiftUI 6** и **SwiftData**. Оно следует стандартному паттерну MVVM (Model-View-ViewModel), с сильным акцентом на современную конкурентность (`async/await`) и декларативный UI.

## Структура Проекта

```
Sources/
├── App/                 # Точка входа (RecodApp.swift), Глобальное состояние
├── Features/            # Модули функциональности
│   ├── Settings/        # Экран настроек и его компоненты
│   └── History/         # Логика и views истории
├── Core/
│   ├── Utilities/       # Помощники (WindowAccessor и т.д.)
│   └── Models/          # Общие модели (HotKeyShortcut)
├── DesignSystem/        # UI Константы (AppTheme) и Стили
├── UI/                  # Переиспользуемые UI компоненты (KeyView)
└── Model/               # SwiftData Модели (Recording.swift)
```

## Хранение Данных (SwiftData)
Приложение использует SwiftData для сохранения записей.
- **Модель**: `Recording` (в `Sources/Model/Recording.swift`).
- **Контейнер**: Инициализируется в `RecodApp.swift`.
- **Внедрение**: Передается через `.modelContainer` в WindowGroup. `ModelContext` также внедряется в `AppState` для немедленного сохранения новых записей.
- **Использование**: Views используют `@Query` для чтения и `@Environment(\.modelContext)` для записи/удаления.
- **Реактивность**: Когда запись завершается, `AppState` создает объект `Recording` и вставляет его в контекст. `HistoryView` (наблюдающий через `@Query`) обновляется мгновенно.

## Аудио Движок
Запись и воспроизведение аудио обрабатываются `AudioPlayer` и `AudioRecorder`.
- Запись использует `AVAudioEngine` с tap, который конвертирует входящее аудио в **16kHz mono WAV** для WhisperKit.
- Воспроизведение использует `AudioPlayer` и внедряется через `@Environment`.

## Движок Транскрибации
Транскрибация обрабатывается `TranscriptionService` на базе **WhisperKit** (CoreML/ANE).
- Двухэтапный пайплайн: **detectLanguage** → **transcribe (task: .transcribe)** для предотвращения непреднамеренного перевода.
- Модели скачиваются и управляются через `WhisperModelManager` (загрузчик WhisperKit).

## Эффект "Стеклянного" Окна
Для достижения вида "Superwhisper" (глубокая прозрачность):
1.  **NSWindow**: Базовое окно настроено как `isOpaque = false` и `backgroundColor = .clear` через `WindowAccessor`.
2.  **SwiftUI Background**: Корневое view применяет `.background(.ultraThinMaterial)`.
3.  **Результат**: Обои рабочего стола пользователя просвечивают через размытый контент приложения.

## Добавление Новых Функций
1.  **Модель**: Определите структуры данных в `Sources/Model`.
2.  **View**: Создайте UI в `Sources/Features/<FeatureName>`.
3.  **Интеграция**: Добавьте в боковую панель `SettingsView` (если это настройка) или `MenuBarContent` (если это основное действие).
4.  **Стиль**: Строго используйте `AppTheme` для констант верстки.
