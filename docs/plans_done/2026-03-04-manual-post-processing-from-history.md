# Manual Post-Processing from History — Implementation Plan

**Date:** 2026-03-04  
**Goal:** Give completed recordings an inline history action that reruns any post-processing rule and replaces the existing result.

---

## Mini-plan

1. Add `PostProcessingService.runManual` to clear the stored result before invoking `runAction` on the selected rule.
2. Expose `RecordingOrchestrator.runManualPostProcessing` to set the status to `.postProcessing`, call the new service helper, and restore `.completed` (or `.failed`).
3. Teach `HistoryRowView` about available `PostProcessingAction`s, show a compact inline menu when a recording is completed, and call `onRunPostProcessing`.
4. Wire the new closure in `HistoryView` so it forwards through `RecordingOrchestrator`.

---

## Context

Manual post-processing already exists via `PostProcessingService.runAction` and the row UI can render `.postProcessing`; this plan just wires the entry point described above.
