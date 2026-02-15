# AGENTS.md - System Instructions for Project Development

## 1. Project Identity & Role
- **Project Type:** Native macOS Desktop Application.
- **Role:** You are a Senior macOS Engineer specializing in SwiftUI, System Design, and Modern Apple aesthetics (Human Interface Guidelines).
- **Target OS:** macOS 15 Sequoia (latest available target).
- **Language:** Swift 6 (Strict Concurrency).
- **Style:** "Tahoe" / Modern Glass (Translucency, Vibrancy, Floating Windows).

## 2. Design Philosophy ("The Tahoe Look")
**REFERENCE:** See `docs/DESIGN_SYSTEM.md` for explicit constants and guides.

- **Central Theme:** All styling (padding, radii, materials) MUST come from `AppTheme` struct.
  - **NO HARDCODED VALUES.**
- **Materials over Colors:** Use `AppTheme.glassMaterial` instead of solid background colors.
- **Components:**
  - Use `glassRowStyle()` for list items (History, Models, etc).
  - Use `DeleteIconButton` for destructive actions.
  - Use `GlassGroupBoxStyle` for grouped content.
- **Window Style:**
  - Use `WindowAccessor` to enable full transparency.
  - Use custom `SidebarView` (not NavigationSplitView) for collapsing behavior.
- **Typography:** SF Pro.
- **Iconography:** SF Symbols 6.
- **Layout:**
  - Floating content panels with shadows and corner radius (16px via `AppTheme`).
  - Ample whitespace (16px/24px via `AppTheme`).
  - Use `AppTheme.pagePadding` (30pt) for main content areas.

## 3. Architecture & Tech Stack
**REFERENCE:** See `docs/ARCHITECTURE.md` for full architecture details.

- **Framework:** SwiftUI (100% preferred). Use AppKit *only* when SwiftUI lacks specific capability (wrap in `NSViewRepresentable`).
- **Pattern:** MVVM (Model-View-ViewModel).
  - **View:** Declarative UI, purely driven by state.
  - **ViewModel:** `@Observable` class (Swift 5.9+ macro). Handles logic, state, and calls to Services.
  - **Model:** Immutable structs (`Sendable`, `Codable`).
- **State Management:**
  - Use `@Observable` for shared state.
  - Use `Environment` for dependency injection.
- **Concurrency:** Swift Concurrency (`async`/`await`). No GCD (`DispatchQueue`) unless absolutely necessary.
- **Persistence:** SwiftData (preferred) or CoreData if complex relationships required.

## 4. Coding Standards (Strict)
- **Swift 6 Mode:** Code must be fully compatible with Swift 6 strict concurrency checks.
- **No Force Unwraps:** Never use `!` (force unwrap). Use `if let`, `guard let`, or nil-coalescing `??`.
- **Naming:**
  - Variables: `camelCase`.
  - Types: `PascalCase`.
  - Boolean properties should read like questions/statements (e.g., `isVisible`, `hasAccess`).
- **Organization:**
  - Use `// MARK: - Section Name` to organize code within files.
  - One type per file (unless private/fileprivate extensions).
- **Error Handling:** Use strict `do-catch` blocks and custom `Error` enums.

## 5. File Structure
```
Sources/
  App/           # App entry point, WindowGroups, AppState
  Features/      # Feature-based modules (e.g., Library, Player, Settings)
    Components/  # Feature-specific views
    ViewModels/  # Logic
  Core/          # Shared extensions, utilities, networking, models
  DesignSystem/  # Reusable UI components (Buttons, Cards, Effects)
Resources/       # Assets, Strings, Plists
```

## 6. Implementation Workflow
1.  **Analyze:** Understand the user request and required state changes.
2.  **Plan:** Identify which `Feature` or `Core` module needs modification.
3.  **Implement:**
    - Create/Modify `Model` (if needed).
    - Update `ViewModel` with new logic/properties.
    - Implement `View` changes using "Glass" design principles.
    - **Reuse components:** Check `Sources/DesignSystem` before creating new styles.
4.  **Verify:** Ensure Swift 6 compliance and no UI regressions.

## 8. AI & Transcription Engine
- **Engine:** WhisperKit (by Argmax).
- **Architecture:**
  - Optimized for Apple Silicon (Neural Engine + GPU).
  - Uses CoreML models (`.mlmodelc`) instead of raw `.bin` files.
- **Service Layer:** `TranscriptionService` (Singleton, `@MainActor`).
  - **Two-Pass Logic:**
    1.  **Language Detection:** Explicitly runs `kit.detectLanguage()` on the audio file first.
    2.  **Transcription:** Runs `kit.transcribe()` with `task: .transcribe` and the detected language. This prevents accidental translation to English.
- **Model Management:**
  - `WhisperModelManager` handles downloading/deleting models via WhisperKit's built-in downloader.
  - Models are stored in `~/Library/Application Support/Recod/Models/models/argmaxinc/whisperkit-coreml`.

## 9. Audio Recording Format
- Recording uses `AVAudioEngine` with a tap that converts audio to **16kHz mono WAV**.
- This ensures WhisperKit receives consistent PCM data and avoids empty/invalid frames.

## 10. Global Hotkeys System
- **Engine:** Carbon API (`RegisterEventHotKey`/`UnregisterEventHotKey`). This is the only way to register truly global hotkeys on macOS.
- **Architecture:**
  - `HotKeyShortcut` — `Codable`/`Sendable` struct storing `keyCode` (UInt32, Carbon virtual key) and `modifiers` (UInt32, Carbon modifier flags: `cmdKey`, `shiftKey`, `optionKey`, `controlKey`).
  - `HotKeyManager` — singleton (`@MainActor`, `ObservableObject`) managing registration, unregistration, and persistence via `UserDefaults`.
  - `HotKeyRecorderView` — SwiftUI component for interactive shortcut capture using `NSEvent.addLocalMonitorForEvents`.
- **Default Shortcut:** `⌘⇧R` (Cmd+Shift+R).
- **Persistence:** Shortcuts are saved to `UserDefaults` as JSON-encoded `HotKeyShortcut`.
- **Key Mapping:** `HotKeyShortcut.keyName(for:)` maps Carbon `kVK_*` codes to human-readable strings. Supports A-Z, 0-9, F1-F12, Space, arrows, punctuation.
- **Validation:** At least one modifier is required for non-F-key shortcuts. F-keys can be registered standalone.

## 11. Window Focus & Activation Policy (CRITICAL)
> **This is the #1 source of bugs in this project. Read carefully.**

- The app is a **MenuBar-only app** (`MenuBarExtra`), which means macOS sets its activation policy to `.accessory` by default.
- `.accessory` apps **cannot receive keyboard focus** — keyboard events go to the app behind.
- **Overlay window** (`AppDelegate.setupOverlayWindow`):
  - Uses `NSWindow` with `styleMask: [.borderless, .nonactivatingPanel]` and `level: .floating`.
  - This is **correct** — overlay must float above everything and NOT steal focus from the active app.
  - **Never add `.titled` or remove `.nonactivatingPanel`** from the overlay window.
- **Settings window** (`WindowGroup(id: "settings")`):
  - **Must NOT use `window.level = .floating`** — this prevents normal focus behavior.
  - Uses `WindowAccessor` only for cosmetic configuration (transparency, title bar, shadow).
  - Activation via `NSApp.activate(ignoringOtherApps: true)` in `.onAppear`.
- **Hotkey Recorder focus workaround** (`HotKeyRecorderView.startRecording`):
  - Temporarily switches `NSApp.setActivationPolicy(.regular)` — this makes the app a "normal" app that can receive keyboard events.
  - Calls `NSApp.activate(ignoringOtherApps: true)` and makes the window key.
  - After recording finishes or is cancelled, restores `NSApp.setActivationPolicy(.accessory)`.
   - **This pattern must be used whenever keyboard input capture is needed.**

## 12. Release Strategy & Sparkle Integration
- **Framework:** Sparkle 2 (SPM dependency).
- **Update Mechanism:**
  - `UpdaterManager` (`@Observable`) wraps `SPUStandardUpdaterController`.
  - Sparkle is **only initialized** when running as a `.app` bundle to prevent crashes during debug (`make run`).
- **CI/CD:** GitHub Actions (`.github/workflows/release.yml`).
  - Triggered by `make release` (pushes git tag).
  - Automatically builds `.app`, signs with EdDSA key, zips, generates `appcast.xml`, and publishes to GitHub Releases.
- **Versioning:** `MAJOR.MINOR` (e.g., 1.01, 1.02).
  - Minor version auto-increments via Makefile.
  - Major version manual trigger: `make release MAJOR=2`.
- **Artifacts:**
  - `Recod.app` must contain `Contents/Frameworks/Sparkle.framework` and have `@rpath` set correctly (handled by `make app` / CI).

## 13. System Instructions: Creating New Pages
**Always check `docs/DESIGN_SYSTEM.md` first.**

When adding a new Settings Page or Feature View:

1.  **Use `SettingsHeaderView`:**
    - Do NOT create custom headers with `GroupBox`.
    - Use standardization:
      ```swift
      SettingsHeaderView(
          title: "Page Title",
          subtitle: "Explanation...",
          systemImage: "icon.name"
      )
      ```
2.  **Use `AppTheme` Constants:**
    - Spacing: `AppTheme.spacing` (12)
    - Padding: `AppTheme.pagePadding` (30) for main containers.
3.  **List Items:**
    - Use `GlassRowStyle` for list items.
    - Implement hover with `.onHover { isHovering = $0 }`.
4.  **Buttons:**
    - Use standard buttons from `Sources/DesignSystem/StandardButtons.swift` (`DeleteIconButton`, etc).
    - For main actions, use `.bordered` style (gray), not `.borderedProminent` (blue), unless it is the primary call to action in a modal.
