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

## 7. Critical Behaviors & Latency Handling
- **Audio Recording:**
  - **Start:** `AudioRecorder` uses `engine.prepare()` before starting to pre-warm hardware.
  - **Stop:** `stopRecording()` includes a **0.5s delay** before stopping the engine to capture the "tail" of speech (preventing cut-off).
  - **UI UX:** The `OverlayView` implements a **fake loading state (0.5s)** when recording starts. This forces the user to wait slightly before speaking, ensuring the audio engine is fully stable and AGC is active. **DO NOT REMOVE THIS DELAY.**
