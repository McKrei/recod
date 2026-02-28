# Parakeet-TDT-0.6B-V3 Integration (sherpa-onnx)

## Overview

Recod natively supports two speech recognition engines:
1. **WhisperKit** (Apple Neural Engine optimized, via CoreML)
2. **Parakeet** (NVIDIA NeMo Parakeet-TDT-0.6B-V3, CPU optimized, via ONNX Runtime + sherpa-onnx)

This document details how the Parakeet engine is integrated, as its architecture differs significantly from WhisperKit due to its reliance on C/C++ libraries and ONNX Runtime.

---

## 1. Engine Selection & UI (`AppState` & Settings)

The active transcription engine is controlled by `TranscriptionEngine` enum (stored in `UserDefaults` via `AppState.selectedEngine`).

- **UI Location**: `ModelsSettingsView` displays a segmented picker to switch the settings view between engines.
- **Auto-Selection**: Changing the picker tab does *not* switch the engine. The engine is only switched when a user explicitly clicks a downloaded model row.
- **Model Managers**: Both `WhisperModelManager` and `ParakeetModelManager` run independently, but `AppState` routes recording actions strictly to the active engine's services.

## 2. Core Library: `sherpa-onnx`

Because `sherpa-onnx` does not support Swift Package Manager (SPM) natively and requires a large static `onnxruntime` dependency, it is integrated as a **Local SPM Package**.

### Architecture of `Packages/SherpaOnnx`
```
Packages/SherpaOnnx/
├── Package.swift               // Local SPM manifest
├── sherpa-onnx.xcframework     // Pre-built static library (contains libsherpa-onnx-all.a)
├── Sources/
│   ├── CSherpaOnnx/            // C-module wrapper
│   │   ├── include/
│   │   │   ├── module.modulemap // Exposes C-API to Swift
│   │   │   └── sherpa-onnx/c-api/c-api.h
│   │   └── empty.c             // Required by SPM to compile the C target
│   └── SherpaOnnxSwift/        // Swift Wrapper
│       └── SherpaOnnx.swift    // Native Swift API bridging the C calls
```

### Build Process (Behind the scenes)
The `xcframework` was built using `build-swift-macos.sh` from the sherpa-onnx repository. 
Crucially, the default build script does not bundle `libonnxruntime.a`. We had to manually extract all static archives (onnxruntime, kaldi-native-fbank, ucx) using `libtool` and merge them into a massive ~150MB `libsherpa-onnx-all.a` before creating the XCFramework.

## 3. Audio Pipeline

Parakeet strictly requires **16kHz, Mono, Float32** audio samples.

### `AudioRecorder` modifications
Instead of keeping a full array of all recorded samples (which caused `O(N^2)` memory copying issues and 0-second file bugs during long recordings), `AudioRecorder` provides:
- `getAudioSamples()`: Returns the full buffer (used by WhisperKit for timestamp clipping).
- `getNewAudioSamples(from:)`: Returns only the delta (newly recorded samples) since the last index.

### `AudioUtilities`
Batch transcription extracts the WAV file using `AudioUtilities.load16kHzMonoFloatSamples(from:)`. This utility reads native WAV formats (e.g., 48kHz Stereo) and safely converts them using `AVAudioConverter` on a background thread.

## 4. Live Streaming (VAD + Chunking)

WhisperKit uses a `clipTimestamps` approach to streaming (transcribing the whole buffer and clipping confirmed sentences). Parakeet uses a completely different strategy handled by `ParakeetStreamingService`.

### Silero VAD
1. **Silero VAD** model (`silero_vad.onnx`) is loaded into `SherpaOnnxVoiceActivityDetectorWrapper`.
2. Audio is fed into the VAD in strict 512-sample chunks (32ms).
3. VAD detects speech boundaries (start/end of phrases).
4. When VAD flags a speech segment as "finished" (e.g., user pauses for 500ms), the segment is popped from the VAD queue.
5. That exact segment is transcribed immediately by the offline recognizer.

**Advantages**: Fast, perfectly handles trailing speech, CPU usage is minimal when the user is silent.

## 5. Segment Building (`ParakeetSegmentBuilder`)

Sherpa-onnx's Parakeet implementation outputs BPE (Byte Pair Encoding) tokens (e.g., `▁Hello`, ` `, `▁world`), not full words or sentences, along with per-token timestamps.

To reach parity with WhisperKit's `[TranscriptionSegment]`:
1. **BPE to Words**: `ParakeetSegmentBuilder` groups tokens starting with `▁` (U+2581) into logical words, taking the start timestamp of the first token and the end timestamp of the last.
2. **Words to Sentences**: Words are accumulated into segments until a terminal punctuation mark (`.`, `?`, `!`) is encountered.
3. **Time Offsets**: Because streaming feeds independent chunks to the recognizer, `timeOffset` (the VAD start time) is injected into the builder to align the segment accurately with the overall recording time.

## 6. Batch Transcription (`ParakeetTranscriptionService`)

When a recording stops:
1. `AppState.stopRecording()` forces `ParakeetStreamingService` to flush any incomplete speech segments.
2. `AppState` triggers `runBatchTranscription()`.
3. The WAV file is loaded via `AudioUtilities`.
4. The full array of samples is sent to `ParakeetTranscriptionService.shared.transcribe(audioSamples:)`.
5. BPE segments are generated, rules are applied, and the transcription is saved to `SwiftData`.

## Summary of Models
The Parakeet V3 package requires 4 files to function:
- `encoder.int8.onnx`
- `decoder.int8.onnx`
- `joiner.int8.onnx`
- `tokens.txt`

They are managed by `ParakeetModelManager` and stored in `~/Library/Application Support/Recod/Models/parakeet/`.