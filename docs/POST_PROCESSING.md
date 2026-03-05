# Post-Processing (LLM)

## Overview
Post-processing transforms finished transcription text using OpenAI-compatible LLM providers.

Current behavior:
- Only **one auto action** can be active at a time.
- Post-processing runs **after** batch transcription and dictionary replacements.
- Manual post-processing can be triggered from **History** for completed recordings.
- Clipboard insertion uses post-processed text when available (fallback to original transcription on failure).

## Data Model

### `PostProcessingAction` (SwiftData `@Model`)
Stored in local database and configurable in Settings:
- `name`
- `prompt` (supports `${output}` and `${output_with_timestamps}` placeholders)
- `providerID`
- `modelID`
- `isAutoEnabled` (single-active invariant)
- `hotkey` (reserved for future use)

### `PostProcessedResult` (embedded in `Recording`)
Stored in `Recording.postProcessedResults` as external storage:
- input/output message history (`LLMMessage[]`)
- action/provider/model snapshots
- timestamp

### Providers and API Keys
- Built-in providers are hardcoded in `LLMProvider.presets`.
- Custom providers are stored in `UserDefaults` (`LLMProviderStore`).
- API keys are stored in macOS Keychain (`KeychainService`).
- Backup/export never includes API keys.

## Runtime Flow
1. `RecordingOrchestrator.runBatchTranscription` finishes ASR and replacement rules.
2. Fetches `PostProcessingAction` list.
3. If one auto action is enabled:
   - switches status to `.postProcessing`
   - runs `PostProcessingService.runAllAutoEnabled`
   - receives transformed text
4. Clipboard insertion uses transformed text.
5. Recording status switches to `.completed`.

### Manual Flow (History)
1. User opens action menu in `HistoryRowView` and picks an action.
2. `RecordingOrchestrator.runManualPostProcessing` sets status to `.postProcessing`.
3. `PostProcessingService.runManual` clears previous `postProcessedResults` and runs selected action.
4. On success, new single result is saved and status returns to `.completed`.
5. On failure, status also returns to `.completed` (transcription remains valid); error is logged.

## UI

### Settings > Post-Processing
- Add/Edit action modal (`AddActionView`).
- Provider first, then model list loaded from `/models`.
- Prompt is prefilled with:

```text
Transcript:
${output}
```

Available prompt placeholders:
- `${output}` - plain transcription text.
- `${output_with_timestamps}` - transcription with per-segment time labels, one line per segment:

```text
[0:05] First phrase
[0:12] Next phrase
```

If segment timeline is unavailable, `${output_with_timestamps}` falls back to plain transcription text.

### History
- Completed rows with non-empty transcription and existing actions show inline manual run menu.
- Menu label shows either first 3 chars of last action name or `wand.and.stars` placeholder.
- Menu is hidden while row is not in completed state or when there are no actions.
- If post-processing result exists:
  - top text shows **After Post-Processing**
  - expanded block shows **Before Post-Processing** and optional timeline

## Overlay States
- `.transcribing`: red orbital loader, 3 dots.
- `.postProcessing`: blue orbital loader, 5 dots.

All visual constants live in `AppTheme`.

## Save to File
Each post-processing action can optionally save the LLM output to a local file.

### Configuration (per action)
- `saveToFileEnabled` - toggle in AddActionView.
- `saveToFileMode` - `newFile` (creates a file per recording) or `existingFile` (appends to one file).
- `saveToFileTemplate` - filename template with placeholders: `{YYYY}`, `{YY}`, `{MM}`, `{DD}`, `{HH}`, `{mm}`, `{ss}`.
- `saveToFileSeparator` - text inserted between entries (supports `\n`, `\t` escapes).
- `saveToFileExtension` - file extension (`.txt` / `.md`).

### Behavior
- Save runs inside `PostProcessingService.runAction()` after a successful LLM call.
- Works for both auto-enabled and manual (History) runs.
- Errors are logged and do not interrupt clipboard/pipeline flow.
- If file does not exist, it is created; first entry has no leading separator.
- In Settings UI, path state is mode-aware: directory path and append-file path are stored separately while editing the action.
- Runtime validates path type before writing: `newFile` expects a directory path, `existingFile` expects a file path.

### File Paths
- No sandbox: paths are stored as plain strings in SwiftData.
- User selects directory/file via `NSOpenPanel`.
- Add/Edit action form is scrollable; action buttons stay pinned at the bottom for long configurations.

## Logging
Key points are logged to `~/Library/Application Support/Recod/Logs/app.log`:
- provider/model requests
- post-processing start/finish
- output length, changed flag, output preview
- fallback decisions

## Backup / Import / Export

### Export includes
- recordings
- transcription segments
- post-processed results
- replacement rules
- post-processing actions
- custom providers

### Export excludes
- API keys (Keychain-only)

### Import behavior
- duplicate protection for recordings/rules/actions
- custom providers are merged by id/name+baseURL
- if multiple actions are marked auto-enabled, only one remains enabled

## How to Extend in Future (AI Requests)

1. Keep OpenAI-compatible path as baseline (`/v1/chat/completions`).
2. Add provider-specific headers/body only in `LLMService`, not in Views.
3. Keep prompt placeholder contract (`${output}`) backward-compatible.
4. Prefer storing new execution metadata in `PostProcessedResult`, not in `Recording` root.
5. Add tests for DTO/backup compatibility whenever payload schema changes.

For future features (multi-action chains, prompt templates), extend `PostProcessingService` first, then UI.
