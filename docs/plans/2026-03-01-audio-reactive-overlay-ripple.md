# Implementation Plan: Audio-Reactive Ripple Overlay for Recording

**Goal:** Replace the current fixed recording pulse with a real audio-reactive ripple animation around the mic icon, so the overlay visually reflects user speech in real time while preserving the existing Tahoe glass style and low CPU usage.

**Why this change:**
- The current recording overlay (`Sources/Features/OverlayView.swift`) animates a red pulse with a static repeating animation that does not reflect actual input audio.
- Users need a trustworthy live indicator that recording is active and reacting to voice intensity.
- A glassy, subtle, premium animation better fits the design language in `docs/DESIGN_SYSTEM.md` and `AGENTS.md`.

**Research findings (validated):**
- `AudioRecorder` already receives real-time audio frames via `installTap` in `Sources/Core/AudioRecorder.swift`, so no extra capture pipeline is needed.
- The safest low-cost signal for UI reactivity is RMS loudness (amplitude), computed per buffer; FFT is possible but unnecessary for this UX and higher complexity.
- `Accelerate` (`vDSP`) is the recommended Apple path for fast DSP (RMS/normalization) on audio buffers.
- Existing architecture supports this cleanly: `AudioRecorder` -> `AppState` binding -> `OverlayView` rendering.
- Must preserve current audio graph constraints from `AGENTS.md`: no tap sample-rate forcing, no graph behavior changes.

---

## Scope

### In scope
- Add real-time audio level extraction from mic input in `AudioRecorder`.
- Expose a smoothed normalized level for UI.
- Bind that level into `AppState`.
- Rework recording-state UI in `OverlayView` to render audio-reactive ripples in glass/Tahoe style.
- Add throttling and smoothing to avoid jitter and excessive redraws.

### Out of scope
- FFT spectral visualizer, bars, or full waveform graph.
- Changes to transcription logic.
- Changes to system-audio routing model.
- Global redesign of non-recording overlay states (`.transcribing`, `.success`, `.error`).

---

## Current State (Codebase Map)

- `Sources/Core/AudioRecorder.swift`
  - Owns `AVAudioEngine` lifecycle and recording tap.
  - Tap writes WAV and streaming buffer (`processBufferForStreaming`).
  - Has `@Published isRecording`, but no UI-oriented audio-level signal.

- `Sources/App/AppState.swift`
  - Holds `overlayStatus`, `isOverlayVisible`, `isRecording`.
  - Subscribes to `audioRecorder.$isRecording`.
  - No published overlay audio intensity yet.

- `Sources/Features/OverlayView.swift`
  - Recording visual is static pulse (`isAnimating`) + mic icon.
  - Has fake delay for UI readiness.

- `Sources/DesignSystem/AppTheme.swift`
  - Central design constants/materials required by project rules.

---

## Design Requirements (from user + project rules)

- Must remain in transparent 3D/glass aesthetic:
  - Keep `AppTheme.glassMaterial` base container.
  - Use subtle highlights/strokes and soft shadows, not flat solid blocks.
- Reactive behavior:
  - Waves expand further with louder speech.
  - Calm idle movement when user is silent (avoid dead/static UI).
- Performance:
  - Avoid per-sample UI updates.
  - Throttle and smooth values before entering SwiftUI.
- Reliability:
  - No changes that can break recording graph or sample-rate safety constraints.

---

## Target Architecture

### Data flow
1. Audio buffer arrives in `AudioRecorder.installTap` callback.
2. DSP helper computes RMS on mic channel and maps to normalized `0...1` level.
3. Recorder stores latest raw level and updates a throttled `@Published` UI level (`audioLevel`) at fixed cadence (for example 20 Hz).
4. `AppState` subscribes to `audioRecorder.$audioLevel` and mirrors it to `overlayAudioLevel`.
5. `OverlayView` uses `overlayAudioLevel` to drive ripple scale/opacity/blur.

### Signal model
- `rawLevel`: immediate normalized value from current buffer.
- `smoothedLevel`: low-pass filtered value used by UI to prevent jitter.
- `peakHold` (optional): short-lived boost for punchy wave attack.

---

## Detailed Task Plan

### Task 1: Add audio-level extraction in `AudioRecorder`

**File:** `Sources/Core/AudioRecorder.swift`

**Step 1.1 - Add DSP and state properties**
- Import `Accelerate`.
- Add recorder properties for level extraction:
  - thread-safe storage for latest raw level;
  - `@Published public private(set) var audioLevel: Float = 0`;
  - update throttling task/timer state;
  - smoothing parameters (`attack`, `release`, min dB, max dB).

**Step 1.2 - Compute loudness from tap buffer**
- In tap callback, after file write and existing `processBufferForStreaming(buffer)`, call a new helper:
  - `processBufferForLevel(buffer)`.
- Helper behavior:
  - choose mic channel (bus path is left-panned mic; for robustness use channel 0 and fallback average);
  - compute RMS with `vDSP_rmsqv`;
  - convert RMS to dB (`20 * log10(max(rms, epsilon))`);
  - clamp to configured dynamic range (example `-50...0 dB`);
  - normalize to `0...1`.

**Step 1.3 - Throttle and publish level for UI**
- Start a lightweight publish loop when recording starts:
  - every ~50 ms read latest raw level;
  - apply smoothing (faster attack, slower release);
  - publish to `audioLevel` on `MainActor`.
- Stop/cancel loop in `stopRecording()` and `teardownGraph()`.
- Reset `audioLevel` to `0` when recording stops.

**Step 1.4 - Concurrency correctness**
- Keep heavy DSP off main thread (inside tap callback queue).
- Publish only through `MainActor`.
- Ensure no retain cycles in loop/task closures.

**Acceptance criteria for Task 1**
- `AudioRecorder.audioLevel` moves in real time with speech.
- Value stays in `0...1` and returns toward `0` in silence.
- No regression in recording start/stop behavior.

---

### Task 2: Expose overlay level in `AppState`

**File:** `Sources/App/AppState.swift`

**Step 2.1 - Add UI-facing state**
- Add `@Published var overlayAudioLevel: Float = 0`.

**Step 2.2 - Bind recorder level**
- Extend `setupBindings()` with subscription to `audioRecorder.$audioLevel`.
- Receive on main run loop and assign to `overlayAudioLevel`.

**Step 2.3 - Reset strategy**
- Ensure `overlayAudioLevel` is reset to `0` when recording finishes/fails.

**Acceptance criteria for Task 2**
- `OverlayView` can consume a stable, main-thread-safe audio intensity signal via `appState`.

---

### Task 3: Replace static pulse with audio-reactive glass ripples

**Primary file:** `Sources/Features/OverlayView.swift`

**Optional extracted component (if file grows):**
- `Sources/Features/Components/RecordingRippleLayer.swift`

**Step 3.1 - Keep base glass container**
- Preserve outer glass circle style (`AppTheme.glassMaterial`, light stroke, soft shadow).
- Do not replace with opaque solid red backgrounds.

**Step 3.2 - New recording visual layers**
- Replace current single pulse with 2-3 ripple layers driven by `overlayAudioLevel`:
  - inner ripple: tight response, subtle opacity;
  - middle ripple: medium expansion;
  - outer ripple: longest expansion, highest fade.
- Each layer derives:
  - `scale = baseScale + overlayAudioLevel * factor`;
  - `opacity = baseOpacity + overlayAudioLevel * factor` (with upper bound);
  - optional tiny blur increase with level for depth.

**Step 3.3 - Smooth animation feel**
- Use spring/ease animation on `overlayAudioLevel` changes.
- Keep motion elegant and not hyperactive.
- Keep mic icon as center anchor (red accent remains).

**Step 3.4 - Preserve existing state transitions**
- Do not break current transition logic for `.transcribing`, `.success`, `.error`.
- Keep startup delay behavior unless it conflicts with immediate responsiveness.

**Design notes (must follow)**
- Use existing constants/materials from `AppTheme` where possible.
- If any new constants are needed for ripple visuals, add them to `AppTheme` (avoid hardcoded magic values across multiple places).

**Acceptance criteria for Task 3**
- In recording mode, waves visibly react to speaking volume.
- In silence, waves settle smoothly (no harsh flicker).
- Visual remains clearly Tahoe/glass and consistent with the app.

---

### Task 4: Calibrate responsiveness and CPU impact

**Files:**
- `Sources/Core/AudioRecorder.swift`
- `Sources/Features/OverlayView.swift`

**Step 4.1 - Calibration parameters**
- Tune dB window, smoothing, and update frequency for natural response.
- Ensure low speech is still visible but background noise does not constantly trigger max ripples.

**Step 4.2 - Performance sanity**
- Verify no excessive memory growth, no noticeable UI stutter.
- Confirm overlay remains smooth during streaming transcription.

**Acceptance criteria for Task 4**
- Stable animation with low CPU overhead.
- No dropped interaction responsiveness in overlay.

---

### Task 5: Testing and verification

**Build verification**
- Command: `swift build`
- Optional runtime check: `make run`

**Manual functional test checklist**
1. Start recording in a quiet room:
   - overlay appears, mic icon visible, ripples are minimal/idle.
2. Speak softly:
   - ripples expand modestly and consistently.
3. Speak loudly/clap:
   - ripples expand further with clear visual difference.
4. Stop recording:
   - ripples stop, overlay transitions to existing transcribing/success/error states unchanged.
5. Toggle "Record System Audio" on and off:
   - mic-driven ripple still works, no permission regressions.
6. Long session (2-3 min):
   - no visible lag buildup, no runaway animation artifacts.

**Edge-case test checklist**
- Microphone permission denied: overlay error path still works.
- Very noisy background: animation not permanently saturated.
- AirPods/Bluetooth path: start/stop still releases mic correctly (HFP/A2DP behavior unaffected).

**Optional automated tests (if test target is introduced in this task)**
- Add pure function tests for level normalization and smoothing math:
  - input dB below floor -> output 0;
  - input dB near 0 -> output near 1;
  - release smoothing decays gradually.

---

## Risks and mitigations

- **Risk:** jittery visuals from raw audio spikes.
  - **Mitigation:** low-pass smoothing + capped range + throttled UI updates.

- **Risk:** CPU overhead from too frequent updates.
  - **Mitigation:** 20 Hz publish cadence and lightweight math.

- **Risk:** accidental recording regressions.
  - **Mitigation:** do not alter graph topology/sample-rate logic; isolate to additional signal extraction only.

---

## Execution Notes for the Implementing Agent

- Do not change transcription flow or model-loading logic.
- Do not force 16kHz or touch tap format assumptions.
- Keep changes localized to overlay/reactive signal path.
- Maintain strict Swift 6 concurrency safety.
- Preserve Tahoe design language and reuse `AppTheme` constants/materials.

---

## Definition of Done

- Recording overlay shows audio-reactive ripple waves based on real mic loudness.
- Visual style remains transparent/glass/3D-like and consistent with existing app theme.
- Build passes (`swift build`), and manual checklist confirms behavior.
- No regressions in recording lifecycle, permissions, or overlay status transitions.
