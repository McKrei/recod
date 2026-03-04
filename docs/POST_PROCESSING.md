# Post-Processing (LLM)

## Overview
Post-processing transforms finished transcription text using OpenAI-compatible LLM providers.

Current behavior:
- Only **one auto action** can be active at a time.
- Post-processing runs **after** batch transcription and dictionary replacements.
- Clipboard insertion uses post-processed text when available (fallback to original transcription on failure).

## Data Model

### `PostProcessingAction` (SwiftData `@Model`)
Stored in local database and configurable in Settings:
- `name`
- `prompt` (supports `${output}` placeholder)
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

## UI

### Settings > Post-Processing
- Add/Edit action modal (`AddActionView`).
- Provider first, then model list loaded from `/models`.
- Prompt is prefilled with:

```text
Transcript:
${output}
```

### History
- If post-processing result exists:
  - top text shows **After Post-Processing**
  - expanded block shows **Before Post-Processing** and optional timeline

## Overlay States
- `.transcribing`: red orbital loader, 3 dots.
- `.postProcessing`: blue orbital loader, 5 dots.

All visual constants live in `AppTheme`.

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

For future features (multi-action chains, manual run, prompt templates), extend `PostProcessingService` first, then UI.
