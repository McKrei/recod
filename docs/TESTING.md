# Recod Testing Documentation

This document describes the testing architecture, coverage, and guidelines for the Recod project.

## Overview

The testing suite relies completely on the **Swift Testing** framework (`import Testing`, `@Suite`, `@Test`, `#expect`).
**Do not use `XCTest`** for new tests.

Tests are run via the `make test` command, which automatically handles building, code signing with audio entitlements (necessary for hardware mic tests), and running all test suites.

```bash
make test
```

## What is Covered?

The test suite is divided into two primary tiers: Pure Functions (Business Logic) and Audio Hardware (Integrations).

### Tier 1: Pure Functions & Business Logic (~100 tests)
These tests require no mocking, run instantly, and cover the core data transformations and logic of the app.

| Suite | File | What it tests |
|---|---|---|
| `LevenshteinDistanceTests` | `String+Levenshtein.swift` | The DP algorithm for calculating the minimum edit distance. Validates Unicode, empty strings, insertions, deletions, substitutions, and case sensitivity. |
| `TranscriptionFormatterTests` | `TranscriptionFormatter.swift` | Regex-based cleanup of WhisperKit special tokens (`<\|startoftranscript\|>`, `<\|en\|>`, etc.) and whitespaces. |
| `HotKeyShortcutTests` | `HotKeyShortcut.swift` | Key code mapping, macOS standard modifier display ordering (⌃⌥⇧⌘), Codable/Equatable, and conversion between Carbon `UInt32` flags and Cocoa `NSEvent.ModifierFlags`. |
| `ParakeetSegmentBuilderTests` | `ParakeetSegmentBuilder.swift` | BPE token merging (SentencePiece `▁` markers), continuation tokens, sentence splitting via punctuation (`.?!`), and timestamp `timeOffset` calculations. |
| `TextReplacementServiceTests` | `TextReplacementService.swift` | Exact and Fuzzy matching rules. Validates ASR split/merge scenarios (sliding windows `pw-1`, `pw`, `pw+1`), punctuation preservation, distance threshold boundaries depending on word length, and rules priority. Uses in-memory SwiftData `ModelContainer`. |
| `TranscriptionEngineTests` | `TranscriptionEngine.swift` | Enum states, raw values, and computed properties. |
| `TranscriptionSegmentTests` | `Recording.swift` | `TranscriptionSegment` initialization, `Codable`, `Hashable` behavior (identical properties but different UUIDs), and `TranscriptionStatus` transitions. |
| `BatchTranscriptionQueueTests` | `BatchTranscriptionQueue.swift` | FIFO processing, pending-job deduplication by `recordingID`, cancel of pending jobs, propagation of inference biasing to Parakeet/Whisper workers, strict waiting for async completion callbacks, and `clearCache()` guarantees (including error path) using fake workers. |
| `DataBackupServiceTests` | `DataBackupService.swift` | Export/import payload integrity, duplicate skipping, import of post-processing results, import of actions/providers, and single auto-enabled action invariant during import. |

### Tier 2: Audio Engine & Hardware (13 tests)
These tests interact with macOS CoreAudio and `AVAudioEngine`. They are marked as `@Suite(.serialized)` because macOS prevents concurrent capture of the same hardware input.

| Suite | File | What it tests |
|---|---|---|
| `AudioEngineGraphTests` | `AudioEngineGraphTests.swift` | Full `AVAudioEngine` graph construction (`inputNode -> micMixer -> recMixer -> mainMixer`). Validates `installTap` actually receives buffers, WAV file writing works, and tests multiple consecutive record cycles (model-switch regression). |
| `AudioRecorderUnitTests` | `AudioRecorderUnitTests.swift` | CoreAudio probe functions (validating they do not steal the mic via the probeEngine bug). Also tests `AVAudioConverter` streaming format conversions, sample rate align/restore lifecycles (BT HFP fix), and the watchdog algorithm that aborts recording on 0 buffers. |

## What is NOT Covered? (And Why)

1. **UI / SwiftUI Views**
   - Recod's architecture relies heavily on macOS-specific translucent overlays and window management (`NSWindow` level manipulations). Standard SwiftUI snapshot testing provides very low ROI here. UI is tested manually.
2. **Heavy Inference Integrations (`TranscriptionService`, `ParakeetTranscriptionService`)**
   - End-to-end transcription tests require downloading ~1.5GB to ~3GB ML models, which is not suitable for rapid local testing or CI environments.
   - We test the *outputs* and *formatting* of these models (Tier 1) rather than the model inference itself.
3. **`RecordingOrchestrator`**
   - The main state machine is tightly coupled to 8+ Singleton services. Testing it would require extracting protocols for every single dependency, which reduces code readability. We rely on the tested underlying services (Audio Engine, Hotkeys, Text Replacement) instead.
4. **`ClipboardService`**
   - Pasting operations (`CGEvent` simulations) require the test runner to have Accessibility permissions (`AXIsProcessTrusted`). macOS security blocks this by default in test runners.
5. **`HotKeyManager`**
   - Registers actual global hotkeys with Carbon. Testing this causes side-effects on the developer's system during test execution. We test the model (`HotKeyShortcut`) instead.
6. **Live LLM provider integrations (`LLMService`)**
   - End-to-end network tests are intentionally not part of regular test suite due to provider availability, auth, and response drift.
   - We test deterministic persistence/invariants around post-processing via `DataBackupServiceTests` and runtime logs.

## Adding New Tests (Guidelines)

1. **Swift Testing Only:** Use `@Suite`, `@Test`, and `#expect`.
2. **SwiftData Models:** If you need to test a `@Model` (like `ReplacementRule`), create an in-memory container within the test:
   ```swift
   let config = ModelConfiguration(isStoredInMemoryOnly: true)
   let container = try ModelContainer(for: ReplacementRule.self, configurations: config)
   let context = ModelContext(container)
   ```
3. **Audio Tests Pre-requisites:**
   - Any test touching `AVAudioEngine` MUST clean up after itself (`engine.stop()`, `engine = nil`).
   - Before running audio tests, ensure your Mac's default input is the **Built-in Microphone**. Bluetooth HFP devices (AirPods in mic mode) will cause tests to crash due to hardware rate mismatching.
4. **No Mocking Frameworks:** Rely on pure functions and in-memory data structures rather than complex mocking libraries.
