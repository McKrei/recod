# Post-Processing Feature — Implementation Plan

**Goal:** Add AI-powered post-processing of transcription results via OpenAI-compatible LLM APIs. Users can create named "actions" with prompts, assign hotkeys, and enable automatic post-processing after each recording.

**Branch:** `feature/text-post-processing`

**Research Findings:**
- All target providers (except Anthropic) support the OpenAI `/v1/chat/completions` format
- Anthropic is excluded from presets (available via OpenRouter as `anthropic/claude-*`)
- Z.AI base URL: `https://api.z.ai/api/paas/v4`
- OpenAI Chat Completions `messages` array natively supports multi-turn history — architecture is "chat-ready" out of the box
- macOS Keychain is the correct storage for API keys (Security framework, no extra SPM deps)

---

## Architecture Overview

```
Sources/
├── Core/
│   ├── Models/
│   │   ├── LLMProvider.swift          # NEW: Codable config struct (not @Model)
│   │   ├── LLMMessage.swift           # NEW: Codable message struct (role + content)
│   │   └── PostProcessingAction.swift # NEW: @Model SwiftData entity
│   ├── Services/
│   │   ├── LLMService.swift           # NEW: URLSession-based OpenAI-compat client
│   │   ├── PostProcessingService.swift# NEW: Orchestrates running actions on recordings
│   │   └── KeychainService.swift      # NEW: API key read/write via Security framework
├── Features/
│   ├── PostProcessing/
│   │   ├── PostProcessingSettingsView.swift  # NEW: Settings tab
│   │   ├── AddActionView.swift               # NEW: Sheet for creating/editing actions
│   │   ├── ActionRowView.swift               # NEW: Row in action list
│   │   ├── AddProviderView.swift             # NEW: Sheet for configuring provider
│   │   └── ProviderPickerView.swift          # NEW: Inline preset picker component
│   └── History/
│       └── Components/
│           └── PostProcessingResultsView.swift # NEW: Shows results in history row
```

**Modified files:**
- `Sources/Core/Models/Recording.swift` — add `postProcessedResults` field
- `Sources/App/RecodApp.swift` — register `PostProcessingAction` in ModelContainer
- `Sources/Features/SettingsView.swift` — add `.postProcessing` case to `SettingsSelection`
- `Sources/Features/Settings/Views/SidebarView.swift` — add new sidebar item
- `Sources/Core/Orchestration/RecordingOrchestrator.swift` — call PostProcessingService after batch transcription
- `Sources/Features/History/HistoryView.swift` / `HistoryRowView.swift` — show post-processed results

---

## Data Models

### Task 1: Core Data Models

#### 1.1 `LLMMessage` — Codable struct (conversation message)

**File:** `Sources/Core/Models/LLMMessage.swift`

```swift
// Designed for full conversation history (current use: system + user only, 
// but array supports multi-turn for future chat feature)
struct LLMMessage: Codable, Sendable, Identifiable {
    enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }
    var id: UUID
    var role: Role
    var content: String
    var createdAt: Date

    init(role: Role, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.createdAt = Date()
    }
}
```

**Why array/history matters:** `LLMService.complete()` accepts `[LLMMessage]`. Today we pass `[system, user]`. In future chat feature, we append `assistant` responses and new `user` messages to the same array — zero architecture changes needed.

#### 1.2 `LLMProvider` — Codable config struct (NOT SwiftData @Model)

**File:** `Sources/Core/Models/LLMProvider.swift`

```swift
// Preset providers are hardcoded constants.
// Custom providers are persisted in UserDefaults as JSON-encoded array.
// API keys are stored separately in Keychain keyed by provider.id.

enum BuiltinProviderID: String, CaseIterable {
    case openAI       = "openai"
    case openRouter   = "openrouter"
    case groq         = "groq"
    case cerebras     = "cerebras"
    case zAI          = "zai"
    case custom       = "custom"
}

struct LLMProvider: Codable, Identifiable, Sendable {
    var id: String          // BuiltinProviderID.rawValue for presets, UUID string for custom
    var displayName: String
    var baseURL: String
    var isCustom: Bool
    var defaultModels: [String]   // Suggested models shown in picker (empty for custom)
    
    static let presets: [LLMProvider] = [
        LLMProvider(id: "openai",     displayName: "OpenAI",     baseURL: "https://api.openai.com/v1",            isCustom: false, defaultModels: ["gpt-4o", "gpt-4o-mini", "o3-mini"]),
        LLMProvider(id: "openrouter", displayName: "OpenRouter", baseURL: "https://openrouter.ai/api/v1",         isCustom: false, defaultModels: ["openai/gpt-4o", "anthropic/claude-3-5-sonnet", "google/gemini-2.0-flash"]),
        LLMProvider(id: "groq",       displayName: "Groq",       baseURL: "https://api.groq.com/openai/v1",       isCustom: false, defaultModels: ["llama-3.3-70b-versatile", "llama3-8b-8192"]),
        LLMProvider(id: "cerebras",   displayName: "Cerebras",   baseURL: "https://api.cerebras.ai/v1",           isCustom: false, defaultModels: ["llama-3.3-70b", "llama3.1-8b"]),
        LLMProvider(id: "zai",        displayName: "Z.AI",       baseURL: "https://api.z.ai/api/paas/v4",         isCustom: false, defaultModels: ["glm-4.7", "glm-5"]),
    ]
}
```

#### 1.3 `PostProcessingAction` — SwiftData `@Model`

**File:** `Sources/Core/Models/PostProcessingAction.swift`

```swift
@Model final class PostProcessingAction {
    @Attribute(.unique) var id: UUID
    var name: String               // User-defined, e.g. "Fix Grammar", "Meeting Notes"
    var prompt: String             // System prompt. Empty = passthrough (clean only)
    var providerID: String         // LLMProvider.id
    var modelID: String            // e.g. "gpt-4o-mini"
    var isAutoEnabled: Bool        // Run automatically after each recording
    var hotkey: HotKeyShortcut?    // Optional, Codable (existing type)
    var sortOrder: Int             // For user reordering
    var createdAt: Date

    init(name: String, prompt: String, providerID: String, modelID: String) {
        self.id = UUID()
        self.name = name
        self.prompt = prompt
        self.providerID = providerID
        self.modelID = modelID
        self.isAutoEnabled = false
        self.sortOrder = 0
        self.createdAt = Date()
    }
}
```

#### 1.4 `PostProcessedResult` — Codable struct (stored inside Recording)

**NOT a separate @Model** — stored as `@Attribute(.externalStorage)` array inside `Recording`.

```swift
struct PostProcessedResult: Codable, Identifiable, Sendable {
    var id: UUID
    var actionID: UUID
    var actionName: String    // Snapshot of name at time of execution
    var providerID: String    // Snapshot
    var modelID: String       // Snapshot
    var messages: [LLMMessage]   // Full conversation history (system + user + assistant)
    var createdAt: Date
    
    // Convenience: the final assistant response
    var outputText: String {
        messages.last(where: { $0.role == .assistant })?.content ?? ""
    }
}
```

#### 1.5 Modify `Recording.swift`

Add one field:

```swift
@Attribute(.externalStorage)
var postProcessedResults: [PostProcessedResult]?
```

And new status case:

```swift
enum TranscriptionStatus: String, Codable {
    case pending
    case streamingTranscription
    case transcribing
    case postProcessing    // NEW
    case completed
    case failed
}
```

---

## Services

### Task 2: KeychainService

**File:** `Sources/Core/Services/KeychainService.swift`

Simple wrapper around Security framework. No SPM deps needed.

```swift
enum KeychainService {
    static let service = "ai.recod.llm-providers"
    
    static func saveAPIKey(_ key: String, forProviderID providerID: String) throws
    static func loadAPIKey(forProviderID providerID: String) -> String?
    static func deleteAPIKey(forProviderID providerID: String) throws
}
```

### Task 3: LLMService

**File:** `Sources/Core/Services/LLMService.swift`

```swift
actor LLMService {
    static let shared = LLMService()
    
    func complete(
        messages: [LLMMessage],
        providerID: String,
        modelID: String
    ) async throws -> LLMMessage
    
    func postProcess(
        text: String,
        systemPrompt: String,
        providerID: String,
        modelID: String
    ) async throws -> String
    
    func fetchModels(providerID: String) async throws -> [String]
}
```

### Task 4: PostProcessingService

**File:** `Sources/Core/Services/PostProcessingService.swift`

```swift
@MainActor
final class PostProcessingService {
    static let shared = PostProcessingService()
    
    func runAction(_ action: PostProcessingAction, on recording: Recording, context: ModelContext) async throws
    func runAllAutoEnabled(on recording: Recording, context: ModelContext, actions: [PostProcessingAction]) async throws
}
```

---

## UI Components

### Task 5: Settings — New Tab

- Add `.postProcessing` to `SettingsSelection`
- `PostProcessingSettingsView` (Main tab layout)
- `ActionRowView` (Row item)
- `AddActionView` (Sheet to add/edit actions)
- `ProviderPickerView`
- `AddProviderView` (Sheet for custom providers/keys)

### Task 6: History — Show Post-Processing Results

- `PostProcessingResultsView` (Expandable section below transcription)
- Integrate into `HistoryRowView`
- Add "Run Action" to context menu

### Task 7: Overlay State

- Reuse existing `.transcribing` orbital loader state for `.postProcessing` phase in `OverlayState.swift`.

### Task 8: HotKey Integration for Actions

- Extend `HotKeyManager` with `[UUID: () -> Void]` dictionary to support multiple dynamic action triggers.

