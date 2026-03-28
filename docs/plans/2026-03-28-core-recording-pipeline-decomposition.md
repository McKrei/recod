# Plan: Core Recording Pipeline Decomposition

Date: 2026-03-28
Priority: P1
Estimated effort: 3-5 days
Risk: high
Recommended owner: senior macOS engineer

## Goal

Split the recording runtime into smaller, testable components without changing user-visible behavior.

## Why This Work Exists

Two files currently carry too much of the runtime flow:

- `Sources/Core/Orchestration/RecordingOrchestrator.swift`
- `Sources/Core/AudioRecorder.swift`

These files currently combine multiple responsibilities that should evolve independently:

- recording lifecycle;
- overlay state updates;
- model readiness checks;
- streaming start/stop;
- finalization and clipboard behavior;
- SwiftData persistence;
- retranscription scheduling;
- audio graph setup/teardown;
- system audio capture;
- recording file path management.

This makes changes risky, weakens testability, and violates the intended architecture described in `docs/ARCHITECTURE.md`.

## Current Problems

### Oversized orchestration object

`Sources/Core/Orchestration/RecordingOrchestrator.swift` currently owns too many concerns:

- user-triggered start/stop/cancel;
- preload and model readiness;
- streaming orchestration for Whisper and Parakeet;
- recording persistence;
- replacement rule fetch and application;
- post-processing trigger;
- clipboard insertion;
- retranscribe and batch queue callbacks.

### Oversized audio facade

`Sources/Core/AudioRecorder.swift` currently mixes:

- permission checks;
- graph construction;
- ScreenCaptureKit hookup;
- file creation and path resolution;
- watchdog logic;
- stream-buffer lifecycle;
- audio-level publishing.

## Scope

This plan covers the recording pipeline only.

### In scope

- decomposition of `RecordingOrchestrator`;
- decomposition of `AudioRecorder` internals;
- clearer service boundaries and protocols where useful;
- targeted tests for extracted pure logic and orchestration helpers.

### Out of scope

- redesigning overlay visuals;
- changing transcription algorithms;
- replacing SwiftData;
- changing the user-facing recording workflow.

## Target State

The resulting architecture should look roughly like this:

- `RecordingOrchestrator`: high-level coordinator only.
- `RecordingSessionController`: start/stop/cancel session transitions.
- `RecordingFinalizationPipeline`: final transcription resolution, replacements, post-processing, clipboard insertion.
- `RecordingPersistenceService`: create/update `Recording` models and persist final state.
- `RetranscriptionCoordinator`: only batch queue and retranscription integration.
- `AudioRecorder`: thin facade over smaller internal collaborators.
- `AudioGraphController`: owns `AVAudioEngine` graph lifecycle.
- `SystemAudioCaptureService`: owns ScreenCaptureKit stream lifecycle.
- `RecordingFileFactory` or `RecordingOutputWriter`: owns file URL creation and file-writing concerns.

Exact naming can vary, but responsibility boundaries should be preserved.

## Mandatory Constraints

This work must preserve the following invariants from `AGENTS.md`:

- no forced 16kHz in the audio graph;
- tap must use native node format;
- sample-rate alignment must happen before graph setup;
- graph teardown must fully release the engine;
- overlay should switch to transcribing immediately on stop;
- menu bar app focus behavior must remain unchanged;
- do not introduce new force unwraps.

## Task Breakdown

### Task 1: Map current orchestration responsibilities

Read and annotate responsibilities in:

- `Sources/Core/Orchestration/RecordingOrchestrator.swift`
- `Sources/Core/AudioRecorder.swift`

Produce an internal engineering note or PR notes grouping methods by concern:

- session control;
- engine/model preparation;
- streaming lifecycle;
- finalization;
- persistence;
- retranscription;
- audio graph;
- file output;
- system audio capture.

Deliverable: a responsibility map used to guide extraction.

### Task 2: Extract finalization pipeline from `RecordingOrchestrator`

Move the logic that happens after recording stops into a dedicated component.

Candidate responsibilities:

- resolve final transcription source;
- apply replacement rules;
- fetch and apply post-processing actions;
- determine clipboard text;
- log final outcome;
- update final overlay success/error state.

Likely methods to move or rewrite around:

- `processFinalRecording(...)`
- `runBatchTranscription(...)`
- `resolveFinalTranscription(...)`
- `resolveWhisperFinalTranscription(...)`
- `resolveParakeetFinalTranscription(...)`

Deliverable: `RecordingOrchestrator` delegates finalization rather than owning all of it inline.

### Task 3: Extract persistence responsibilities

Separate creation and updates of `Recording` SwiftData models from the session coordinator.

Candidate responsibilities:

- create new recording entry;
- update status transitions;
- persist transcription/segments;
- persist post-processing results or failures;
- fetch recording by ID for batch callbacks.

Potential destinations:

- `Sources/Core/Services/RecordingPersistenceService.swift`
- or `Sources/Core/Orchestration/RecordingPersistenceService.swift`

Deliverable: `RecordingOrchestrator` no longer manually performs most persistence mutations inline.

### Task 4: Extract retranscription-specific coordination

Pull retranscription behavior into a smaller focused coordinator.

Scope includes:

- `retranscribe(recording:)`
- `cancelRetranscribe(recording:)`
- batch queue callback handlers

The batch queue itself already exists in `Sources/Core/Orchestration/BatchTranscriptionQueue.swift`. The goal is to prevent the main recording flow from also owning all retranscription state transitions.

Deliverable: normal recording flow and retranscription flow are easier to reason about independently.

### Task 5: Split `AudioRecorder` internals

Refactor `Sources/Core/AudioRecorder.swift` into smaller internal collaborators.

Minimum extraction targets:

1. graph construction and teardown;
2. ScreenCaptureKit system-audio setup/stop;
3. output file URL generation and file setup;
4. watchdog and tap state bookkeeping.

The public surface of `AudioRecorder` may stay mostly unchanged if that reduces migration risk.

Deliverable: `AudioRecorder` becomes a thin facade that coordinates smaller objects instead of containing all implementation details.

### Task 6: Add or extend tests around extracted logic

Add focused tests where extraction creates stable seams.

Good candidates:

- final transcription source selection;
- replacement/post-processing fallback decisions;
- recording persistence transitions;
- watchdog decision logic if extracted into a pure helper.

Do not attempt heavyweight end-to-end inference tests.

## Suggested File Changes

Likely touched files:

- `Sources/Core/Orchestration/RecordingOrchestrator.swift`
- `Sources/Core/AudioRecorder.swift`
- `Sources/Core/Orchestration/BatchTranscriptionQueue.swift`
- `Sources/App/AppState.swift`

Likely new files:

- `Sources/Core/Orchestration/RecordingSessionController.swift`
- `Sources/Core/Orchestration/RecordingFinalizationPipeline.swift`
- `Sources/Core/Services/RecordingPersistenceService.swift`
- `Sources/Core/Orchestration/RetranscriptionCoordinator.swift`
- `Sources/Core/Audio/AudioGraphController.swift`
- `Sources/Core/Audio/SystemAudioCaptureService.swift`
- `Sources/Core/Audio/RecordingFileFactory.swift`

The exact set can be smaller if responsibilities are still clearly separated.

## Acceptance Criteria

- `RecordingOrchestrator` is materially smaller and clearly focused on high-level flow.
- `AudioRecorder` is materially smaller and does not directly own every low-level concern.
- Public recording behavior remains unchanged from the user's perspective.
- Audio invariants from `AGENTS.md` are preserved.
- Retranscription still works through the batch queue.
- New extractions do not increase UI-level singleton coupling.
- `make test` passes.

## Verification Steps

Minimum verification:

1. `make test`
2. manual smoke test:
   - start/stop normal recording;
   - start/stop with system audio disabled;
   - if possible, test system audio enabled path;
   - confirm overlay state transitions;
   - confirm clipboard insertion still works;
   - confirm retranscribe still works from History.

## Risks

- Breaking subtle audio graph timing or teardown behavior.
- Breaking overlay state transitions.
- Accidentally changing persistence timing and producing missing or duplicated `Recording` updates.
- Creating too many protocols or abstractions that add indirection without real value.

## Implementation Notes

- Prefer thin extractions that preserve current logic before trying to redesign behavior.
- Extract pure decision logic first, then move stateful behavior.
- Keep migration incremental: move one concern, run tests, then proceed.
- If a symbol is widely referenced, use semantic refactoring tools to update references safely.
