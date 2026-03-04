# Manual Post-Processing from History — Implementation Plan

**Date:** 2026-03-04  
**Goal:** Add an inline button to `HistoryRowView` that lets the user manually run any post-processing action on a completed recording. The result is saved as `PostProcessedResult`, replacing any previous result for that recording.

---

## Background & Context

### Current state
- Post-processing runs **automatically** after every transcription if any `PostProcessingAction` has `isAutoEnabled = true`.
- There is **no way** to manually trigger post-processing from History.
- `Recording.postProcessedResults` is a `[PostProcessedResult]?` stored as `.externalStorage`. According to business rules confirmed by the product owner, **only one result per recording is valid at any time** — the array effectively holds a single item.
- `PostProcessingService.runAction(_:on:context:)` already handles the full LLM call + appending result + saving context.

### Key files
| File | Role |
|---|---|
| `Sources/Core/Services/PostProcessingService.swift` | LLM orchestration, result persistence |
| `Sources/Core/Orchestration/RecordingOrchestrator.swift` | Recording lifecycle, status transitions |
| `Sources/Features/History/Views/HistoryRowView.swift` | Row UI, all inline controls |
| `Sources/Features/History/HistoryView.swift` | List host, SwiftData context, callbacks |
| `Sources/Core/Models/PostProcessedResult.swift` | Value-type result struct |
| `Sources/Core/Models/PostProcessingAction.swift` | SwiftData `@Model` for actions |
| `Sources/Core/Models/Recording.swift` | SwiftData `@Model` for recordings |

### Relevant types (condensed)

```swift
// Recording (@Model)
var transcriptionStatus: TranscriptionStatus?   // .completed | .postProcessing | ...
var transcription: String?
var postProcessedResults: [PostProcessedResult]? // treated as single-item array

// PostProcessedResult (struct, Codable)
var actionID: UUID
var actionName: String
var outputText: String  // computed from messages

// PostProcessingAction (@Model)
var id: UUID
var name: String
var prompt: String       // supports ${output} placeholder
var providerID: String
var modelID: String
var isAutoEnabled: Bool
var sortOrder: Int
```

### Existing status rendering in `HistoryRowView`
`HistoryRowView` already handles `.postProcessing` status — it shows a `ProgressView` + "Post-processing..." label. **No new status rendering code is needed.**

---

## Architecture

```
User taps inline button  →  Menu(actions)  →  user selects action
        ↓
HistoryRowView.onRunPostProcessing(action)  [closure]
        ↓
HistoryView calls RecordingOrchestrator.shared.runManualPostProcessing(recording:action:)
        ↓
RecordingOrchestrator.runManualPostProcessing  [MainActor, spawns Task]
   • status → .postProcessing  +  save
   • PostProcessingService.shared.runManual(action, on: recording, context:)
        ↓
PostProcessingService.runManual
   • clears postProcessedResults = nil
   • calls existing runAction(_:on:context:)
        ↓  (LLM call)
   • runAction appends PostProcessedResult, saves context
        ↓
RecordingOrchestrator (back in Task)
   • status → .completed  +  save
   • on error → status → .failed  +  log
```

---

## Task 1 — `PostProcessingService`: add `runManual`

**File:** `Sources/Core/Services/PostProcessingService.swift`

Add the following method **after** `runAllAutoEnabled`:

```swift
/// Manually run a specific action on a recording.
/// Clears any existing post-processed result before running.
func runManual(_ action: PostProcessingAction, on recording: Recording, context: ModelContext) async throws {
    guard let transcription = recording.transcription,
          !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        await FileLogger.shared.log(
            "Manual post-processing skipped: empty transcription for recording=\(recording.id)",
            level: .warning
        )
        return
    }

    // Clear previous result (business rule: one result per recording)
    recording.postProcessedResults = nil
    try context.save()

    try await runAction(action, on: recording, context: context)
}
```

**Notes:**
- `runAction` already handles logging (start / success / failure).
- Clearing + saving before the LLM call ensures the UI immediately loses the old result and shows the `.postProcessing` spinner (set by the orchestrator).
- No changes to `runAction` or `runAllAutoEnabled`.

---

## Task 2 — `RecordingOrchestrator`: add `runManualPostProcessing`

**File:** `Sources/Core/Orchestration/RecordingOrchestrator.swift`

Add the following method near the existing `retranscribe` / `cancelRetranscribe` methods:

```swift
/// Manually triggers post-processing for a completed recording.
/// Runs asynchronously — multiple recordings can be processed in parallel.
@MainActor
func runManualPostProcessing(recording: Recording, action: PostProcessingAction) {
    guard recording.transcription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
        return
    }

    let context = ModelContext(sharedModelContainer)

    Task {
        await FileLogger.shared.log(
            "Manual post-processing requested: recording=\(recording.id), action=\(action.name)",
            level: .info
        )

        recording.transcriptionStatus = .postProcessing
        try? context.save()

        do {
            try await PostProcessingService.shared.runManual(action, on: recording, context: context)
            recording.transcriptionStatus = .completed
            try? context.save()

            await FileLogger.shared.log(
                "Manual post-processing completed: recording=\(recording.id), action=\(action.name)",
                level: .info
            )
        } catch {
            recording.transcriptionStatus = .failed
            try? context.save()

            await FileLogger.shared.log(
                "Manual post-processing failed: recording=\(recording.id), action=\(action.name), error=\(error.localizedDescription)",
                level: .error
            )
        }
    }
}
```

**Notes:**
- `sharedModelContainer` is the existing `ModelContainer` reference used throughout `RecordingOrchestrator`. Check the exact property name in the file — it may be `AppState.shared.modelContainer` or similar. Use the same pattern as in `retranscribe`.
- Spawning a `Task {}` inside a `@MainActor` method means status updates happen on the main actor, which is correct for SwiftUI.
- Each call creates its own `Task` — parallel calls for different recordings are independent.

---

## Task 3 — `HistoryRowView`: inline button

**File:** `Sources/Features/History/Views/HistoryRowView.swift`

### 3.1 — Add closure parameter

Add to the struct's stored properties (alongside existing closures):

```swift
let onRunPostProcessing: (PostProcessingAction) -> Void
```

### 3.2 — Add `@Query` for actions

Add a new property after the existing `@State` declarations:

```swift
@Query(sort: \PostProcessingAction.sortOrder)
private var postProcessingActions: [PostProcessingAction]
```

### 3.3 — Add computed properties

```swift
/// Whether the inline post-processing button should be visible.
private var canRunPostProcessing: Bool {
    recording.transcriptionStatus == .completed &&
    recording.transcription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
    !postProcessingActions.isEmpty
}

/// Label for the inline button:
/// – If a result already exists: first 3 characters of the action name (e.g. "Sum")
/// – If no result yet: sparkles icon as placeholder
@ViewBuilder
private var postProcessingButtonLabel: some View {
    if let actionName = latestPostProcessedResult?.actionName {
        Text(String(actionName.prefix(3)))
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
    } else {
        Image(systemName: "wand.and.stars")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
    }
}
```

### 3.4 — Insert button into the header `HStack`

The header `HStack` currently looks like:

```swift
HStack {
    Text(recording.createdAt.formatted(...))
        .font(.caption)
        .foregroundStyle(.secondary)

    Spacer()

    Text(formatDuration(recording.duration))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.tertiary)
}
```

Replace with:

```swift
HStack {
    Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
        .font(.caption)
        .foregroundStyle(.secondary)

    Spacer()

    // Manual post-processing button (inline, no extra vertical space)
    if canRunPostProcessing {
        Menu {
            ForEach(postProcessingActions) { action in
                Button(action.name) {
                    onRunPostProcessing(action)
                }
            }
        } label: {
            postProcessingButtonLabel
                .frame(width: 28, height: 18)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Run post-processing")
    }

    Text(formatDuration(recording.duration))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.tertiary)
}
```

**Design notes:**
- `Menu { } label: { }` with `.menuStyle(.borderlessButton)` renders a native macOS popover menu without any button chrome — visually matches the existing `doc.on.doc` copy button style.
- `.fixedSize()` prevents the menu from stretching the header row.
- The button is **only visible** when `canRunPostProcessing == true`: completed status + non-empty transcription + at least one action exists.
- While processing (`.postProcessing` status), the button disappears automatically because `canRunPostProcessing` returns `false`.

### 3.5 — Update `#Preview` (if present)

If the file contains a `#Preview` or `PreviewProvider`, add a stub closure:

```swift
HistoryRowView(
    recording: sample,
    audioPlayer: AudioPlayer(),
    onDelete: {},
    onDeleteAudioOnly: {},
    onRetranscribe: {},
    onRunPostProcessing: { _ in }  // ← add this
)
```

---

## Task 4 — `HistoryView`: wire the callback

**File:** `Sources/Features/History/HistoryView.swift`

### 4.1 — Update `HistoryRowView` initialisation

Find the existing `HistoryRowView(...)` call in the `ForEach` and add the new closure:

```swift
HistoryRowView(
    recording: recording,
    audioPlayer: audioPlayer,
    onDelete: { deleteRecording(recording) },
    onDeleteAudioOnly: { deleteAudioOnly(recording) },
    onRetranscribe: { retranscribeRecording(recording) },
    onRunPostProcessing: { action in          // ← add this
        runPostProcessing(recording, action: action)
    }
)
```

### 4.2 — Add the helper method

Add alongside the existing `retranscribeRecording` method:

```swift
private func runPostProcessing(_ recording: Recording, action: PostProcessingAction) {
    RecordingOrchestrator.shared.runManualPostProcessing(recording: recording, action: action)
}
```

---

## Edge Cases & Error Handling

| Scenario | Behaviour |
|---|---|
| No `PostProcessingAction` exists in the DB | Button hidden (`canRunPostProcessing = false`, `postProcessingActions` is empty) |
| `recording.transcription` is `nil` or empty | Button hidden; `runManualPostProcessing` also guards and returns early |
| Status is not `.completed` (e.g. still `.postProcessing`) | Button hidden — `canRunPostProcessing` requires `.completed` |
| Two recordings run post-processing simultaneously | Each is a separate `Task` — fully independent, no shared mutable state |
| LLM call throws an error | Status → `.failed`, error logged via `FileLogger`. Row shows "Transcription failed" state (existing UI) |
| Action is deleted while processing is in-flight | `LLMService` will fail with provider/model lookup error → caught → `.failed` |
| User triggers the button and immediately retranscribes | `retranscribe` sets `transcription = nil` + `postProcessedResults = nil` + status `.queued`. The post-processing Task will either find empty transcription (guard returns early) or context will be stale. Both are safe no-ops. |

---

## Implementation Order

1. `PostProcessingService.swift` — `runManual` (smallest, no dependencies)
2. `RecordingOrchestrator.swift` — `runManualPostProcessing` (depends on step 1)
3. `HistoryRowView.swift` — inline button + `@Query` + closure (depends on step 2 signature)
4. `HistoryView.swift` — wire callback (depends on step 3 signature)

Build and test after step 4. Run `make test` to verify no regressions in existing test suites.

---

## Verification Checklist

- [ ] Tapping the button on a completed recording with actions shows the full action list in a popover menu
- [ ] Selecting an action immediately changes the row to show "Post-processing..." spinner
- [ ] After completion the row shows the new post-processed result with the first 3 characters of the action name on the button
- [ ] Running the same action twice replaces the result (does not accumulate multiple results)
- [ ] Running a different action also replaces the previous result
- [ ] Button is not visible while status is `.postProcessing`, `.transcribing`, `.queued`
- [ ] Button is not visible if `recording.transcription` is empty
- [ ] Button is not visible if there are no `PostProcessingAction` in the database
- [ ] Two recordings can be post-processed in parallel without interfering
- [ ] LLM error sets status to `.failed` and logs the error
- [ ] `make test` passes with no new failures
