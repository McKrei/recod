# User Dictionary & Smart Inference Implementation Plan

**Goal:** Implement context biasing (word boosting) natively in both Parakeet and WhisperKit, add fuzzy string matching for automatic typo correction, and provide a user-friendly configuration UI.
**Research Findings:** 
- **Parakeet (SherpaOnnx)** supports `hotwords_file` and `hotwords_score` directly via C-API and `SherpaOnnxSwift`.
- **WhisperKit** allows context biasing via the `promptTokens` array in `DecodingOptions` (though limited by token length, we can map words to token IDs).
- **SwiftData** is used to store `ReplacementRule`. We will add a `weight` property to denote importance.
- The user wants to keep the existing `textToReplace` and `additionalIncorrectForms` but add "Smart Fuzzy Matching" as a toggle.

---

### Task 1: Update SwiftData Model

**Context:**
- Existing file: `Sources/Core/Models/ReplacementRule.swift`

**Step 1: Add new properties**
We need to add `weight` and `useFuzzyMatching` properties. We give them default values so existing databases don't crash.

- File: `Sources/Core/Models/ReplacementRule.swift`
- Code changes:
  Add `@Attribute var weight: Float = 1.5` 
  Add `@Attribute var useFuzzyMatching: Bool = true`
  Update the `init` method to accept these.

---

### Task 2: Implement Fuzzy String Matching 

**Context:**
- Existing file: `Sources/Core/Services/TextReplacementService.swift`

**Step 1: Add Levenshtein Distance Algorithm**
We need an algorithm to calculate the edit distance between two strings to perform fuzzy matching.

**Step 2: Update `applyReplacements` logic**
- If a rule has `useFuzzyMatching == true`, we tokenize the transcribed text into words.
- For each word, we check its Levenshtein distance against the rule's `textToReplace` and its `additionalIncorrectForms`.
- If the distance is within an acceptable threshold (e.g., <= 2 for words longer than 4 chars, 1 for shorter words), we replace it.
- We still process exact matches (case-insensitive regex) for rules where `useFuzzyMatching == false` or for exact phrase matching.

---

### Task 3: Feed Hotwords into Parakeet (SherpaOnnx)

**Context:**
- Existing file: `Sources/Core/Services/ParakeetTranscriptionService.swift`

**Step 1: Generate Hotwords String**
- We need to fetch all `ReplacementRule` objects.
- Create a space-separated string of all `textToReplace` items.
- Since SherpaOnnx supports individual word scores via text file formatting (e.g., `word 1.5`), we can create a temporary file or use the `hotwords` API directly if supported. Looking at `SherpaOnnxSwift`, it supports `hotwordsFile` in the config, or passing a `hotwords` string dynamically on reset. Since we use `SherpaOnnxOfflineRecognizer`, there is no `reset` method. We must pass it via `hotwordsFile` or `hotwords_buf` in `sherpaOnnxOfflineRecognizerConfig`. 
- Actually, `sherpaOnnxOfflineRecognizerConfig` doesn't expose `hotwords_buf` in Swift currently, but we can write the hotwords to a temporary `.txt` file and pass the path to `hotwordsFile`, setting `hotwordsScore` to the average weight.

**Step 2: Apply to Config**
- In `ParakeetTranscriptionService.prepareModel(modelDir: URL, rules: [ReplacementRule])`:
  - Write rules to `FileManager.default.temporaryDirectory.appendingPathComponent("hotwords.txt")`
  - Format: One word/phrase per line.
  - Set `hotwordsFile = tempPath`, `hotwordsScore = 1.5`.

---

### Task 4: Feed Hotwords into WhisperKit

**Context:**
- Existing file: `Sources/Core/Services/TranscriptionService.swift` and `Sources/Core/Services/StreamingTranscriptionService.swift`

**Step 1: Tokenize Hotwords**
- WhisperKit uses `kit.tokenizer.encode()`.
- We grab all `ReplacementRule` strings, encode them into token IDs.

**Step 2: Inject via `promptTokens`**
- In `TranscriptionService.transcribe()`, populate `options.promptTokens`.
- WhisperKit `DecodingOptions` accepts `promptTokens: [Int]?`. We concatenate the encoded hotwords and pass them in. This gives Whisper the "context" that these words are likely to be spoken.

---

### Task 5: Update the AddReplacementView UI

**Context:**
- Existing file: `Sources/Features/Replacements/AddReplacementView.swift`

**Step 1: Add Weight Picker and Fuzzy Toggle**
- Add `@State private var weight: Float = 1.5`
- Add `@State private var useFuzzyMatching: Bool = true`
- In the `Form`, add a Section for "Advanced".
  - Toggle("Smart Fuzzy Matching", isOn: $useFuzzyMatching)
  - Picker("Priority Weight", selection: $weight) { ... Low (1.0), Normal (1.5), High (2.0) }
- Update `saveRule()` to persist these new values.

---

### Task 6: Hook it all up in AppState

**Context:**
- Existing file: `Sources/App/AppState.swift`

**Step 1: Pass rules to Transcribers**
- Currently, `AppState` fetches rules *after* transcription to run `TextReplacementService`.
- We need to fetch rules *before* calling `TranscriptionService.shared.transcribe` and `ParakeetTranscriptionService.shared.transcribe` so we can pass them down for Hotwords biasing.

### Verification
- Run the app, add a replacement rule with fuzzy matching.
- Speak the word with a slight error, verify the text replacement catches it.
- Verify that hotwords are correctly passed into both engines without crashing.
