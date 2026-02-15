# AGENTS.md - System Instructions for recod

## 1. Project Context
- **Name:** recod
- **Goal:** Lightweight, menu bar audio transcription app (MacWhisper clone).
- **Architecture:** SwiftPM (Executable Target), MVVM, AppState (ObservableObject).
- **Style:** "Tahoe" (Glassmorphism, Translucency, macOS 14+).

## 2. Core Components
- **AudioRecorder:** Uses `AVAudioRecorder` for AAC recording. Handles permissions and metering.
- **OverlayView:** Floating window with real-time waveform visualization. Uses `AppState.audioLevel` (0.0 - 1.0).
- **HotKeyManager:** Carbon-based global hotkey registration (`Cmd+Shift+R`).
- **Logger:** Simple file-based logger in `Application Support`.

## 3. Implementation Rules
- **Swift 6 Concurrency:** Strictly adhere to `Sendable`, `@MainActor`, and `Task` usage. No `DispatchQueue` unless necessary.
- **UI:** Prefer `Material` over colors. Use `ScenePadding` where appropriate.
- **Windows:**
  - `Overlay`: `NSWindow` via `AppDelegate` (level `.floating`, transparent).
  - `Settings`: Custom `WindowGroup` with `.windowStyle(.hiddenTitleBar)` to achieve custom look.
- **State:** Use `AppState.shared` singleton for global state coordination.

## 4. Documentation
- See `docs/overview.md` for high-level architecture.
- Follow `docs/` conventions for any new documentation.

## 5. Build & Run
- Use `swift build` to verify compilation.
- Use Xcode to run and debug (requires signing for microphone access).
