# MacAudio2 - Project Overview

## 1. Description
**MacAudio2** is a native macOS menu bar application designed for quick audio recording and transcription (similar to MacWhisper).

**Key Features:**
*   **Menu Bar App**: Runs in the background (LSUIElement), accessible via a menu bar icon.
*   **Global Hotkey**: Toggle recording instantly with `Cmd+Shift+R`.
*   **Visual Feedback**: Floating "Dynamic Island" style overlay with live waveform visualization.
*   **Audio Capture**: Uses `AVAudioRecorder` to capture high-quality AAC audio.
*   **Privacy First**: Local processing and explicit permission handling.

## 2. Tech Stack
*   **Target OS**: macOS 14.0+ (Sonoma/Sequoia).
*   **Language**: Swift 6 (Strict Concurrency).
*   **UI Framework**: SwiftUI (100%).
*   **Architecture**: MVVM (Model-View-ViewModel) + AppState (ObservableObject singleton).
*   **Audio**: AVFoundation (`AVAudioRecorder`).
*   **System Integration**: Carbon (Global Hotkeys), AppKit (Window Management).
*   **Build System**: Swift Package Manager (Executable Target).

## 3. Project Structure
```
MacAudio2/
├── Sources/
│   ├── App/        # App entry point, AppDelegate, AppState
│   ├── Core/       # Logic: AudioRecorder, HotKeyManager, Logger
│   └── Features/   # UI: OverlayView, SettingsView
├── Package.swift   # SwiftPM Configuration
├── Info.plist      # Application Metadata & Permissions
└── docs/           # Documentation
```

## 4. Design Guidelines ("Tahoe")
*   **Glassmorphism**: Use `.ultraThinMaterial` and `.thickMaterial` for backgrounds.
*   **Translucency**: Windows should feel light and float above content.
*   **Typography**: SF Pro, dynamic type.
*   **Interactions**: Hover effects, smooth animations (Spring).
