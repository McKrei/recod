# Application Architecture

## Overview
Recod is a native macOS application built with **SwiftUI 6** and **SwiftData**. It follows a standard MVVM (Model-View-ViewModel) pattern, with a strong emphasis on modern concurrency (`async/await`) and declarative UI.

## Project Structure

```
Sources/
├── App/                 # App entry point (RecodApp.swift), Global State
├── Features/            # Feature modules
│   ├── SettingsView.swift
│   └── History/         # History feature logic and views
├── Core/
│   └── Utilities/       # Helpers (WindowAccessor, etc.)
├── DesignSystem/        # UI Constants (AppTheme) and Styles
└── Model/               # SwiftData Models (Recording.swift)
```

## Data Persistence (SwiftData)
The app uses SwiftData for persisting recordings.
- **Model**: `Recording` (in `Sources/Model/Recording.swift`).
- **Container**: Initialized in `RecodApp.swift`.
- **Injection**: Passed via `.modelContainer` to the WindowGroup. `ModelContext` is also injected into `AppState` to allow immediate saving of new recordings.
- **Usage**: Views use `@Query` to read and `@Environment(\.modelContext)` to write/delete.
- **Reactivity**: When a recording finishes, `AppState` creates a `Recording` object and inserts it into the context. The `HistoryView` (observing via `@Query`) updates instantly.

## Audio Engine
Audio recording and playback are handled by `AudioPlayer` and `AudioRecorder`.
- Recording uses `AVAudioEngine` with a tap that converts incoming audio to **16kHz mono WAV** for WhisperKit.
- Playback uses `AudioPlayer` and is injected via `@Environment`.

## Transcription Engine
Transcription is handled by `TranscriptionService` backed by **WhisperKit** (CoreML/ANE).
- Two-pass pipeline: **detectLanguage** → **transcribe (task: .transcribe)** to avoid unintended translation.
- Models are downloaded and managed via `WhisperModelManager` (WhisperKit downloader).

## The "Glass" Window Trick
To achieve the "Superwhisper" look (deep transparency):
1.  **NSWindow**: The underlying window is set to `isOpaque = false` and `backgroundColor = .clear` via `WindowAccessor`.
2.  **SwiftUI Background**: The root view applies `.background(.ultraThinMaterial)`.
3.  **Result**: The user's desktop wallpaper shows through blurred behind the app content.

## Adding New Features
1.  **Model**: Define data structures in `Sources/Model`.
2.  **View**: Create the UI in `Sources/Features/<FeatureName>`.
3.  **Integration**: Add to `SettingsView` sidebar (if a setting) or `MenuBarContent` (if a primary action).
4.  **Style**: Strictly use `AppTheme` for layout constants.
