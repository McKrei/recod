# Parakeet V3 (sherpa-onnx) Integration Plan

**Goal:** Add NVIDIA Parakeet-TDT-0.6B-V3 as an alternative transcription engine alongside WhisperKit, using sherpa-onnx for ONNX Runtime inference on CPU. Users can select the engine in Settings, download the model, and use it for both live streaming transcription (VAD + chunk) and batch transcription with full timestamped segments.

**Research Findings:**
- sherpa-onnx provides a C API with Swift wrappers for offline (non-streaming) Parakeet-TDT recognition
- Model: `sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8` (~640 MB, 25 European languages including Russian/Ukrainian)
- Files: `encoder.int8.onnx` (622 MB), `decoder.int8.onnx` (12 MB), `joiner.int8.onnx` (6.1 MB), `tokens.txt` (92 KB)
- Performance: RTF ~0.12-0.33 on Apple Silicon CPU (3-8x realtime). 5-sec recording = ~0.6-1.7 sec transcription
- Timestamps: BPE token-level (need merging to word/segment level)
- No SPM support — must build xcframework manually via `build-swift-macos.sh`
- Thread-safe: can decode on background threads
- Streaming: VAD (Silero) detects speech segments, each chunk decoded by offline recognizer

**Decisions:**
- Streaming strategy: VAD + chunk (Silero VAD detects end of phrase, then transcribe each chunk)
- UI: Tabbed engine selection (WhisperKit | Parakeet) on Models settings page
- Timestamps: Full BPE→word→segment pipeline for parity with WhisperKit segments

---

## Architecture Overview

```
Settings UI
  └── ModelsSettingsView
        ├── [Tab: WhisperKit] → WhisperModelManager (existing)
        └── [Tab: Parakeet]  → ParakeetModelManager (NEW)
                                  ├── download model files from GitHub
                                  └── manage local model directory

AppState (orchestrator)
  ├── selectedEngine: TranscriptionEngine (.whisperKit | .parakeet)
  ├── startRecording()
  │     ├── if .whisperKit → StreamingTranscriptionService (existing)
  │     └── if .parakeet  → ParakeetStreamingService (NEW, VAD + chunk)
  └── stopRecording() → saveRecording()
        ├── if .whisperKit → TranscriptionService.transcribe() (existing)
        └── if .parakeet  → ParakeetTranscriptionService.transcribe() (NEW)

ParakeetTranscriptionService (NEW)
  ├── Loads sherpa-onnx OfflineRecognizer once
  ├── transcribe(audioSamples: [Float]) → (String, [TranscriptionSegment])
  └── BPE token timestamps → word → segment merging

ParakeetStreamingService (NEW)
  ├── Uses sherpa-onnx VAD (Silero) to detect speech segments
  ├── Each complete speech segment → OfflineRecognizer.decode()
  └── Updates Recording.liveTranscription incrementally

AudioRecorder (UNCHANGED)
  └── Produces [Float] 16kHz Mono + WAV file (engine-agnostic)
```

---

## Task 1: Build sherpa-onnx xcframework for macOS

**Context:**
- No SPM support. Must build from source.
- Script: `build-swift-macos.sh` in sherpa-onnx repo
- Produces: `sherpa-onnx.xcframework` (static, universal arm64 + x86_64)

**Step 1: Clone and build**
```bash
cd /tmp
git clone https://github.com/k2-fsa/sherpa-onnx.git
cd sherpa-onnx
./build-swift-macos.sh
```

**Step 2: Locate output**
```
build-swift-macos/sherpa-onnx.xcframework  # Static xcframework
build-swift-macos/build/lib/               # Static libraries
```

**Step 3: Add to Recod project**
- Copy `sherpa-onnx.xcframework` into `Frameworks/` directory in Recod project root
- Copy Swift wrapper: `swift-api-examples/SherpaOnnx.swift` → `Sources/Core/SherpaOnnx/SherpaOnnx.swift`
- Copy bridging header: `swift-api-examples/SherpaOnnx-Bridging-Header.h` → `Sources/Core/SherpaOnnx/SherpaOnnx-Bridging-Header.h`
- Update Xcode project / Package.swift:
  - Add xcframework as binary target or link manually
  - Set `Other Linker Flags: -lc++`
  - Set `Header Search Paths` to include bridging header location
  - Set `Objective-C Bridging Header` path

**Step 4: Verify build**
- Project should compile without errors
- `import` check: SherpaOnnx types are accessible from Swift

**Verification:** `swift build` or Xcode build succeeds with sherpa-onnx linked.

**IMPORTANT NOTE about Package.swift:**
Since Recod uses SwiftPM (Package.swift), the xcframework integration may require:
- Adding it as a `.binaryTarget` in Package.swift
- Or creating a wrapper package that includes the xcframework
- The bridging header approach may not work with pure SwiftPM — may need a C target module map instead

---

## Task 2: Download Parakeet V3 Model Files

**Context:**
- Model URL: `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2`
- VAD model URL: `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx`
- Storage: `~/Library/Application Support/Recod/Models/parakeet/`

**Files after extraction:**
```
~/Library/Application Support/Recod/Models/parakeet/
  sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/
    encoder.int8.onnx     (622 MB)
    decoder.int8.onnx     (12 MB)
    joiner.int8.onnx      (6.1 MB)
    tokens.txt            (92 KB)
  silero_vad.onnx         (1.6 MB)
```

---

## Task 3: TranscriptionEngine Enum

**Context:**
- New file: `Sources/Core/Models/TranscriptionEngine.swift`
- Replaces the implicit "always WhisperKit" assumption

**Code:**
```swift
// Sources/Core/Models/TranscriptionEngine.swift

enum TranscriptionEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    case whisperKit = "whisperKit"
    case parakeet = "parakeet"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .whisperKit: return "WhisperKit"
        case .parakeet: return "Parakeet V3"
        }
    }
    
    var description: String {
        switch self {
        case .whisperKit: return "OpenAI Whisper models via CoreML. GPU/ANE accelerated."
        case .parakeet: return "NVIDIA Parakeet TDT. Fast CPU inference, 25 languages."
        }
    }
}
```

---

## Task 4: ParakeetModelManager

**Context:**
- New file: `Sources/Core/Services/ParakeetModelManager.swift`
- Mirrors WhisperModelManager pattern but with custom download logic (URLSession, tar.bz2 extraction)

**Code:**
```swift
// Sources/Core/Services/ParakeetModelManager.swift

import Foundation
import Observation

enum ParakeetModelType: String, CaseIterable, Identifiable, Codable, Sendable {
    case v3Int8 = "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
    
    var id: String { rawValue }
    var displayName: String { "Parakeet V3 (Int8)" }
    var approximateSize: String { "640 MB" }
    var downloadURL: URL {
        URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/\(rawValue).tar.bz2")!
    }
    var languages: String { "25 European languages (en, ru, de, fr, es...)" }
}

struct ParakeetModel: Identifiable, Equatable, Sendable {
    let type: ParakeetModelType
    var id: String { type.id }
    var name: String { type.displayName }
    var sizeDescription: String { type.approximateSize }
    var isDownloaded: Bool = false
    var isDownloading: Bool = false
    var downloadProgress: Double = 0.0
}

@MainActor @Observable
final class ParakeetModelManager {
    var models: [ParakeetModel]
    var isVADDownloaded: Bool = false
    
    private let modelsDirectory: URL  // ~/Library/Application Support/Recod/Models/parakeet/
    private let vadURL = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx")!
    private var downloadTask: URLSessionDownloadTask?
    
    init() {
        // Setup modelsDirectory
        // Check which models are already downloaded on disk
        // Check if silero_vad.onnx exists
    }
    
    func downloadModel(_ model: ParakeetModel) {
        // 1. Download .tar.bz2 via URLSession with progress tracking
        // 2. Extract to modelsDirectory using Process("tar", arguments: ["xjf", ...])
        //    OR use a Swift tar library
        // 3. Download silero_vad.onnx if not present
        // 4. Update model.isDownloaded = true
    }
    
    func cancelDownload(_ model: ParakeetModel) {
        downloadTask?.cancel()
        // Reset UI state
    }
    
    func deleteModel(_ model: ParakeetModel) {
        // Remove model directory from disk
    }
    
    // Returns path to model directory (for passing to sherpa-onnx)
    func getModelDirectory(for modelId: String) -> URL? {
        let dir = modelsDirectory.appendingPathComponent(modelId)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }
    
    func getVADModelPath() -> URL? {
        let path = modelsDirectory.appendingPathComponent("silero_vad.onnx")
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }
}
```

**Key differences from WhisperModelManager:**
- Custom download logic (can't use WhisperKit.download())
- tar.bz2 extraction needed
- Separate VAD model download
- Different model directory structure

---

## Task 5: ParakeetTranscriptionService (Batch)

**Context:**
- New file: `Sources/Core/Services/ParakeetTranscriptionService.swift`
- Loads sherpa-onnx OfflineRecognizer, provides `transcribe()` matching the same return signature as TranscriptionService

**Code:**
```swift
// Sources/Core/Services/ParakeetTranscriptionService.swift

import Foundation

@MainActor
final class ParakeetTranscriptionService {
    static let shared = ParakeetTranscriptionService()
    
    private var recognizer: SherpaOnnxOfflineRecognizer?
    private var currentModelDir: URL?
    
    // MARK: - Model Loading
    
    func prepareModel(modelDir: URL) {
        guard currentModelDir != modelDir else { return }
        
        let encoderPath = modelDir.appendingPathComponent("encoder.int8.onnx").path
        let decoderPath = modelDir.appendingPathComponent("decoder.int8.onnx").path
        let joinerPath = modelDir.appendingPathComponent("joiner.int8.onnx").path
        let tokensPath = modelDir.appendingPathComponent("tokens.txt").path
        
        // Build sherpa-onnx config
        var modelConfig = sherpaOnnxOfflineModelConfig()
        // NeMo transducer paths
        // modelConfig.transducer.encoder = encoderPath (as C string)
        // modelConfig.transducer.decoder = decoderPath
        // modelConfig.transducer.joiner = joinerPath
        // modelConfig.tokens = tokensPath
        // modelConfig.numThreads = 4
        // modelConfig.modelType = "nemo_transducer"
        
        var config = sherpaOnnxOfflineRecognizerConfig()
        config.modelConfig = modelConfig
        
        self.recognizer = SherpaOnnxOfflineRecognizer(config: &config)
        self.currentModelDir = modelDir
    }
    
    // MARK: - Batch Transcription (from audio samples)
    
    func transcribe(audioSamples: [Float], sampleRate: Int = 16000) -> (String, [TranscriptionSegment]) {
        guard let recognizer = recognizer else { return ("", []) }
        
        let stream = recognizer.createStream()
        stream.acceptWaveform(samples: audioSamples, sampleRate: Int32(sampleRate))
        recognizer.decode(stream)
        
        let result = recognizer.getResult(stream)
        let text = result.text
        
        // Extract token-level timestamps and merge to segments
        let segments = buildSegments(from: result)
        
        return (text, segments)
    }
    
    // MARK: - Batch Transcription (from WAV file)
    
    func transcribe(audioURL: URL) async throws -> (String, [TranscriptionSegment]) {
        // 1. Load WAV file samples (or use sherpa-onnx's wave reader)
        // 2. Resample to 16kHz mono if needed
        // 3. Call transcribe(audioSamples:)
        // NOTE: can run on background thread since sherpa-onnx is thread-safe
        
        return await Task.detached { [weak self] in
            guard let self = self else { return ("", []) }
            let samples = self.loadWavSamples(from: audioURL)
            return await MainActor.run {
                self.transcribe(audioSamples: samples)
            }
        }.value
    }
    
    // MARK: - Timestamp Merging (BPE → Word → Segment)
    
    private func buildSegments(from result: SherpaOnnxOfflineRecongitionResult) -> [TranscriptionSegment] {
        // result.tokens = ["▁Hello", ",", "▁my", "▁name", "▁is", "▁John", "."]
        // result.timestamps = [0.0, 0.32, 0.48, 0.64, 0.80, 0.96, 1.12]
        // result.tdt_durations = [0.32, 0.16, 0.16, 0.16, 0.16, 0.16, 0.08]
        
        // Step 1: Merge BPE tokens into words
        // A token starting with "▁" (U+2581) or space begins a new word
        // Word start time = first token's timestamp
        // Word end time = last token's timestamp + duration
        
        // Step 2: Group words into segments by punctuation (. ? !)
        // Segment start = first word's start
        // Segment end = last word's end
        // Segment text = joined words
        
        // Step 3: Return [TranscriptionSegment]
        var segments: [TranscriptionSegment] = []
        
        // ... merging logic (~50-80 lines) ...
        
        return segments
    }
    
    func clearCache() {
        recognizer = nil
        currentModelDir = nil
    }
    
    private func loadWavSamples(from url: URL) -> [Float] {
        // Use AVAudioFile to read and convert to 16kHz mono Float32
        // Similar to AudioRecorder's processBufferForStreaming logic
        return []
    }
}
```

---

## Task 6: ParakeetStreamingService (VAD + Chunk)

**Context:**
- New file: `Sources/Core/Services/ParakeetStreamingService.swift`
- Uses Silero VAD from sherpa-onnx to detect speech segments
- When a speech segment ends, sends it to OfflineRecognizer for transcription
- Updates Recording.liveTranscription incrementally

**Architecture:**
```
AudioRecorder.getAudioSamples() → [Float] 16kHz mono
    ↓ (polled every 100ms)
Silero VAD.acceptWaveform(samples)
    ↓ (speech segment detected)
OfflineRecognizer.decode(speechSegment)
    ↓
Recording.liveTranscription += result.text
Recording.segments.append(newSegments)
```

**Code:**
```swift
// Sources/Core/Services/ParakeetStreamingService.swift

import Foundation
import SwiftData

@MainActor
final class ParakeetStreamingService: ObservableObject {
    static let shared = ParakeetStreamingService()
    
    private var isStreaming = false
    private var streamingTask: Task<Void, Never>?
    
    private var vad: SherpaOnnxVoiceActivityDetectorWrapper?
    private var lastProcessedSampleCount = 0
    private var accumulatedSegments: [TranscriptionSegment] = []
    private var accumulatedText: String = ""
    private var currentTimeOffset: TimeInterval = 0
    
    func startStreaming(
        recording: Recording,
        audioRecorder: AudioRecorder,
        modelContext: ModelContext,
        modelDir: URL,
        vadModelPath: URL
    ) {
        guard !isStreaming else { return }
        isStreaming = true
        lastProcessedSampleCount = 0
        accumulatedSegments = []
        accumulatedText = ""
        currentTimeOffset = 0
        
        // 1. Initialize VAD
        setupVAD(vadModelPath: vadModelPath)
        
        // 2. Ensure ParakeetTranscriptionService has model loaded
        ParakeetTranscriptionService.shared.prepareModel(modelDir: modelDir)
        
        // 3. Start polling loop
        streamingTask = Task { [weak self] in
            guard let self = self else { return }
            
            while self.isStreaming {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms poll
                
                let allSamples = audioRecorder.getAudioSamples()
                guard allSamples.count > self.lastProcessedSampleCount else { continue }
                
                // Feed only NEW samples to VAD
                let newSamples = Array(allSamples[self.lastProcessedSampleCount...])
                self.lastProcessedSampleCount = allSamples.count
                
                // Feed to VAD in 512-sample chunks (32ms at 16kHz)
                self.feedVAD(samples: newSamples)
                
                // Check if VAD has completed speech segments
                while self.vad?.hasVoiceSegment() == true {
                    guard let speechSamples = self.vad?.popVoiceSegment() else { break }
                    
                    // Transcribe this speech segment
                    let (text, segments) = ParakeetTranscriptionService.shared
                        .transcribe(audioSamples: speechSamples)
                    
                    // Adjust segment timestamps by accumulated offset
                    let adjustedSegments = segments.map { seg in
                        TranscriptionSegment(
                            start: seg.start + self.currentTimeOffset,
                            end: seg.end + self.currentTimeOffset,
                            text: seg.text
                        )
                    }
                    
                    // Update accumulated state
                    self.currentTimeOffset += TimeInterval(speechSamples.count) / 16000.0
                    self.accumulatedSegments.append(contentsOf: adjustedSegments)
                    self.accumulatedText += (self.accumulatedText.isEmpty ? "" : " ") + text
                    
                    // Update Recording model
                    recording.liveTranscription = self.accumulatedText
                    recording.segments = self.accumulatedSegments
                    try? modelContext.save()
                }
            }
        }
    }
    
    func stopStreaming() {
        isStreaming = false
        streamingTask?.cancel()
        streamingTask = nil
        vad = nil
    }
    
    private func setupVAD(vadModelPath: URL) {
        var vadConfig = sherpaOnnxVadModelConfig()
        // vadConfig.sileroVad.model = vadModelPath.path (as C string)
        // vadConfig.sileroVad.threshold = 0.5
        // vadConfig.sileroVad.minSilenceDuration = 0.5
        // vadConfig.sileroVad.minSpeechDuration = 0.25
        // vadConfig.sampleRate = 16000
        // vadConfig.windowSize = 512
        
        self.vad = SherpaOnnxVoiceActivityDetectorWrapper(config: &vadConfig)
    }
    
    private func feedVAD(samples: [Float]) {
        // Feed samples to VAD in windowSize chunks (512 samples)
        let windowSize = 512
        var offset = 0
        while offset + windowSize <= samples.count {
            let chunk = Array(samples[offset..<offset + windowSize])
            vad?.acceptWaveform(samples: chunk)
            offset += windowSize
        }
    }
}
```

**Key differences from WhisperKit streaming:**
- No `clipTimestamps` needed — each speech segment is transcribed independently
- No segment "confirmation" logic needed — VAD determines segment boundaries
- Faster feedback: as soon as VAD detects end of speech, text appears
- Timestamps are adjusted by `currentTimeOffset` to maintain global timeline

---

## Task 7: Update AppState for Engine Selection

**Context:**
- Existing file: `Sources/App/AppState.swift`
- Add engine selection, route to correct services

**Changes:**

```swift
// Add to AppState properties:
public let parakeetModelManager = ParakeetModelManager()

public var selectedEngine: TranscriptionEngine {
    get {
        TranscriptionEngine(rawValue: UserDefaults.standard.string(forKey: "selectedEngine") ?? "whisperKit") ?? .whisperKit
    }
    set {
        self.objectWillChange.send()
        UserDefaults.standard.set(newValue.rawValue, forKey: "selectedEngine")
    }
}
```

**Modify `startRecording()`:**
```swift
func startRecording() async {
    // ... existing pre-checks ...
    
    switch selectedEngine {
    case .whisperKit:
        // Existing WhisperKit flow (unchanged)
        if let modelId = whisperModelManager.selectedModelId,
           let modelURL = whisperModelManager.getModelURL(for: modelId) {
            await TranscriptionService.shared.prepareModel(modelURL: modelURL)
            // ... start audioRecorder ...
            StreamingTranscriptionService.shared.startStreaming(
                recording: recording,
                audioRecorder: audioRecorder,
                modelContext: modelContext,
                modelURL: modelURL
            )
        }
        
    case .parakeet:
        if let modelId = parakeetModelManager.models.first(where: { $0.isDownloaded })?.id,
           let modelDir = parakeetModelManager.getModelDirectory(for: modelId),
           let vadPath = parakeetModelManager.getVADModelPath() {
            ParakeetTranscriptionService.shared.prepareModel(modelDir: modelDir)
            // ... start audioRecorder ...
            ParakeetStreamingService.shared.startStreaming(
                recording: recording,
                audioRecorder: audioRecorder,
                modelContext: modelContext,
                modelDir: modelDir,
                vadModelPath: vadPath
            )
        }
    }
}
```

**Modify `saveRecording()` (batch transcription after recording stops):**
```swift
func saveRecording(url: URL) async {
    // ... existing duration calculation ...
    
    switch selectedEngine {
    case .whisperKit:
        // Existing flow (unchanged)
        let (text, segments) = try await TranscriptionService.shared.transcribe(
            audioURL: url, modelURL: modelURL
        )
        // ...
        
    case .parakeet:
        // Load WAV samples and transcribe
        let (text, segments) = try await ParakeetTranscriptionService.shared.transcribe(
            audioURL: url
        )
        let finalText = TextReplacementService.shared.applyRules(to: text)
        recording.transcription = finalText
        recording.segments = segments
        recording.transcriptionStatus = .completed
        // Copy to clipboard, paste, etc.
    }
}
```

**Modify `stopRecording()` to stop correct streaming service:**
```swift
func stopRecording() async {
    switch selectedEngine {
    case .whisperKit:
        StreamingTranscriptionService.shared.stopStreaming()
    case .parakeet:
        ParakeetStreamingService.shared.stopStreaming()
    }
    // ... rest of existing stopRecording logic ...
}
```

---

## Task 8: Update ModelsSettingsView (Tabbed UI)

**Context:**
- Existing file: `Sources/Features/Models/ModelsSettingsView.swift`
- Add segmented picker for engine selection + tab-specific content

**Code:**
```swift
// Sources/Features/Models/ModelsSettingsView.swift

struct ModelsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: TranscriptionEngine = .whisperKit
    
    var body: some View {
        VStack(spacing: AppTheme.spacing) {
            SettingsHeaderView(
                title: "Models",
                subtitle: "Choose transcription engine and model",
                systemImage: "cpu"
            )
            
            // Engine selector (segmented picker)
            Picker("Engine", selection: $selectedTab) {
                ForEach(TranscriptionEngine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppTheme.pagePadding)
            .onChange(of: selectedTab) { _, newValue in
                appState.selectedEngine = newValue
            }
            .onAppear {
                selectedTab = appState.selectedEngine
            }
            
            // Engine description
            Text(selectedTab.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppTheme.pagePadding)
            
            // Tab content
            switch selectedTab {
            case .whisperKit:
                WhisperModelsListView()  // Extract existing WhisperKit model list
                
            case .parakeet:
                ParakeetModelsListView()  // NEW
            }
            
            Spacer()
        }
    }
}
```

**New file: `Sources/Features/Models/ParakeetModelsListView.swift`**
```swift
struct ParakeetModelsListView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: AppTheme.spacing) {
            ForEach(appState.parakeetModelManager.models) { model in
                ParakeetModelRow(
                    model: model,
                    onDownload: { appState.parakeetModelManager.downloadModel(model) },
                    onCancel: { appState.parakeetModelManager.cancelDownload(model) },
                    onDelete: { appState.parakeetModelManager.deleteModel(model) }
                )
            }
        }
        .padding(.horizontal, AppTheme.pagePadding)
    }
}
```

**New file: `Sources/Features/Models/ParakeetModelRow.swift`**
```swift
struct ParakeetModelRow: View {
    let model: ParakeetModel
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .fontWeight(.medium)
                Text(model.sizeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if model.isDownloading {
                ProgressView(value: model.downloadProgress)
                    .frame(width: 100)
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle")
                }
            } else if model.isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                DeleteIconButton(action: onDelete)
            } else {
                Button("Download") { onDownload() }
                    .buttonStyle(.bordered)
            }
        }
        .glassRowStyle(isHovering: isHovering)
        .onHover { isHovering = $0 }
    }
}
```

---

## Task 9: BPE Token → Segment Merger

**Context:**
- New file: `Sources/Core/Services/ParakeetSegmentBuilder.swift`
- Converts sherpa-onnx token-level output into `[TranscriptionSegment]`

**Code:**
```swift
// Sources/Core/Services/ParakeetSegmentBuilder.swift

import Foundation

struct ParakeetSegmentBuilder {
    
    /// Merges BPE tokens into word-level groups, then groups words into
    /// sentence segments split on punctuation (.?!)
    ///
    /// - Parameters:
    ///   - tokens: BPE token strings (e.g., ["▁Hello", ",", "▁my", "▁name"])
    ///   - timestamps: Start time for each token (seconds)
    ///   - durations: Duration of each token (seconds, TDT-specific)
    ///   - timeOffset: Global offset to add to all timestamps
    /// - Returns: Array of TranscriptionSegment
    static func buildSegments(
        tokens: [String],
        timestamps: [Float],
        durations: [Float],
        timeOffset: TimeInterval = 0
    ) -> [TranscriptionSegment] {
        guard !tokens.isEmpty else { return [] }
        
        // Step 1: Merge BPE tokens into words
        var words: [(text: String, start: TimeInterval, end: TimeInterval)] = []
        var currentWord = ""
        var wordStart: TimeInterval = 0
        var wordEnd: TimeInterval = 0
        
        for i in 0..<tokens.count {
            let token = tokens[i]
            let start = TimeInterval(timestamps[i]) + timeOffset
            let duration = i < durations.count ? TimeInterval(durations[i]) : 0.08
            let end = start + duration
            
            // "▁" (U+2581) prefix means start of new word (SentencePiece convention)
            let isNewWord = token.hasPrefix("\u{2581}") || token.hasPrefix(" ")
            let cleanToken = token
                .replacingOccurrences(of: "\u{2581}", with: "")
                .replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
            
            if isNewWord && !currentWord.isEmpty {
                // Save previous word
                words.append((text: currentWord, start: wordStart, end: wordEnd))
                currentWord = cleanToken
                wordStart = start
                wordEnd = end
            } else {
                if currentWord.isEmpty {
                    wordStart = start
                }
                currentWord += cleanToken
                wordEnd = end
            }
        }
        
        // Don't forget last word
        if !currentWord.isEmpty {
            words.append((text: currentWord, start: wordStart, end: wordEnd))
        }
        
        // Step 2: Group words into segments by sentence-ending punctuation
        let sentenceEnders: Set<Character> = [".", "?", "!"]
        var segments: [TranscriptionSegment] = []
        var segmentWords: [(text: String, start: TimeInterval, end: TimeInterval)] = []
        
        for word in words {
            segmentWords.append(word)
            
            // Check if word ends with sentence-ending punctuation
            if let lastChar = word.text.last, sentenceEnders.contains(lastChar) {
                let segmentText = segmentWords.map(\.text).joined(separator: " ")
                let segment = TranscriptionSegment(
                    start: segmentWords.first!.start,
                    end: segmentWords.last!.end,
                    text: segmentText.trimmingCharacters(in: .whitespaces)
                )
                segments.append(segment)
                segmentWords = []
            }
        }
        
        // Remaining words as final segment (no sentence ender)
        if !segmentWords.isEmpty {
            let segmentText = segmentWords.map(\.text).joined(separator: " ")
            let segment = TranscriptionSegment(
                start: segmentWords.first!.start,
                end: segmentWords.last!.end,
                text: segmentText.trimmingCharacters(in: .whitespaces)
            )
            segments.append(segment)
        }
        
        return segments
    }
}
```

---

## Task 10: WAV File Reader for Batch Transcription

**Context:**
- The batch transcription path receives a WAV file URL (recorded at 48kHz stereo native HW format)
- sherpa-onnx needs 16kHz mono Float32 samples
- Can reuse AVAudioFile + AVAudioConverter approach from AudioRecorder

**Code (add to ParakeetTranscriptionService):**
```swift
/// Loads a WAV file and converts to 16kHz Mono Float32 samples
private func loadWavSamples(from url: URL) -> [Float] {
    do {
        let audioFile = try AVAudioFile(forReading: url)
        let sourceFormat = audioFile.processingFormat
        
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else { return [] }
        
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else { return [] }
        
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: frameCount
        ) else { return [] }
        
        try audioFile.read(into: sourceBuffer)
        
        let outputCapacity = AVAudioFrameCount(
            Double(frameCount) * (16000.0 / sourceFormat.sampleRate)
        ) + 4096
        
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputCapacity
        ) else { return [] }
        
        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }
        
        guard error == nil,
              let channelData = outputBuffer.floatChannelData else { return [] }
        
        return Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(outputBuffer.frameLength)
        ))
    } catch {
        print("[ParakeetTranscriptionService] Failed to load WAV: \(error)")
        return []
    }
}
```

---

## Task 11: Optional — Add `transcriptionEngine` field to Recording model

**Context:**
- Existing file: `Sources/Core/Models/Recording.swift`
- Track which engine produced the transcription (useful for debugging/UI)

**Change:**
```swift
// Add to Recording @Model class:
var transcriptionEngine: String?  // "whisperKit" or "parakeet"
```

Set in `AppState.saveRecording()`:
```swift
recording.transcriptionEngine = selectedEngine.rawValue
```

---

## Execution Order

| # | Task | Depends On | Estimated Time |
|---|------|-----------|---------------|
| 1 | Build sherpa-onnx xcframework | - | 1-2 hours |
| 2 | Download model files for testing | - | 30 min |
| 3 | TranscriptionEngine enum | - | 15 min |
| 4 | ParakeetModelManager | Task 3 | 2-3 hours |
| 5 | ParakeetTranscriptionService (batch) | Tasks 1, 3 | 2-3 hours |
| 6 | ParakeetStreamingService (VAD + chunk) | Tasks 1, 5 | 3-4 hours |
| 7 | Update AppState | Tasks 3, 4, 5, 6 | 1-2 hours |
| 8 | Update ModelsSettingsView (tabs) | Tasks 3, 4 | 2-3 hours |
| 9 | BPE Segment Builder | - | 1-2 hours |
| 10 | WAV file reader | - | 30 min |
| 11 | Recording model update | Task 3 | 15 min |

**Total estimated time: 2-3 days**

**Critical path: Tasks 1 → 5 → 6 → 7 (sherpa-onnx build → batch → streaming → wiring)**

---

## Risk Assessment

### High Risk
- **sherpa-onnx + SwiftPM compatibility:** sherpa-onnx produces an xcframework, but Recod uses Package.swift (not Xcode project). Bridging headers don't work in pure SwiftPM. May need to create a C module map wrapper or switch to Xcode project.
  - **Mitigation:** Create a local SPM package that wraps the xcframework with a proper `module.modulemap`

### Medium Risk
- **tar.bz2 extraction on macOS:** Swift doesn't have native tar.bz2 support. Options: (a) shell out to `/usr/bin/tar`, (b) use a Swift library like `SWCompression`. Shelling out is simpler and reliable on macOS.
  - **Mitigation:** Use `Process("/usr/bin/tar", arguments: ["xjf", path])` — already available on all macOS

### Medium Risk
- **Audio format mismatch:** sherpa-onnx expects exactly 16kHz mono. Our stream buffer is already 16kHz mono, but the WAV file is 48kHz stereo. Need careful resampling for batch mode.
  - **Mitigation:** WAV reader in Task 10 handles resampling via AVAudioConverter (proven pattern from existing AudioRecorder code)

### Low Risk
- **VAD timing accuracy:** Silero VAD speech/silence boundaries affect transcript quality. May need tuning of `minSilenceDuration` and `threshold` parameters.
  - **Mitigation:** Start with defaults (threshold=0.5, minSilence=0.5s), tune based on testing

### Low Risk
- **BPE token merging edge cases:** Punctuation-only tokens, numbers, special characters may not merge correctly.
  - **Mitigation:** Test with diverse audio samples, add special case handling as discovered

---

## Testing Strategy

1. **Unit test: ParakeetSegmentBuilder** — verify BPE→word→segment merging with known token sequences
2. **Integration test: Batch transcription** — transcribe a known WAV file, compare text output
3. **Integration test: Streaming** — record 10 seconds, verify live text updates
4. **UI test: Model download/delete** — verify download progress, extraction, cleanup
5. **UI test: Engine switching** — switch between WhisperKit and Parakeet, verify correct engine is used
6. **Edge case: Short recordings** — verify behavior with <1 second audio
7. **Edge case: System audio** — verify Parakeet handles system audio the same as mic audio
