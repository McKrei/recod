# Implementation Plan: Optional Clipboard Saving with Paste Preservation

**Goal:** Add a toggle to control whether transcribed text is permanently saved to the clipboard, while still allowing `Cmd+V` simulation to work seamlessly without destroying the user's previous clipboard contents (text, images, files) when the feature is disabled.
**Research Findings:** macOS requires `NSPasteboard` to contain the text to be pasted when simulating `Cmd+V`. To insert text without affecting the clipboard, we must temporarily swap the clipboard contents, simulate the keystrokes, wait for the OS to process the paste, and then restore the original `NSPasteboardItem` array.

---

### Task 1: Update AppState

**Context:**
- Existing file: `Sources/App/AppState.swift`

**Step 1: Implementation**
- Add the `saveToClipboard` property to manage the state via `UserDefaults`.
- Initialize its default value if it doesn't exist (default: `true`).
- Update `runBatchTranscription` to read this property and pass it to `ClipboardService`.

**Code/Logic changes in `Sources/App/AppState.swift`:**
1. Add the property (around line 35):
```swift
    public var saveToClipboard: Bool {
        get { 
            if UserDefaults.standard.object(forKey: "saveToClipboard") == nil {
                UserDefaults.standard.set(true, forKey: "saveToClipboard")
            }
            return UserDefaults.standard.bool(forKey: "saveToClipboard") 
        }
        set {
            self.objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "saveToClipboard")
        }
    }
```
2. Modify the end of `runBatchTranscription` (around line 322):
```swift
            // Before:
            // ClipboardService.shared.copyToClipboard(finalText)
            // Task {
            //     ClipboardService.shared.pasteToActiveApp()
            // }

            // After:
            let shouldSaveToClipboard = self.saveToClipboard
            Task {
                await ClipboardService.shared.insertText(finalText, preserveClipboard: !shouldSaveToClipboard)
            }
```

---

### Task 2: Enhance ClipboardService for Safe Swapping

**Context:**
- Existing file: `Sources/Core/Services/ClipboardService.swift`

**Step 1: Implementation**
- Replace the separated `copyToClipboard` and `pasteToActiveApp` logic with a unified `insertText(_:preserveClipboard:)` method.
- Add robust `NSPasteboard` backup and restore mechanisms.

**Code/Logic changes in `Sources/Core/Services/ClipboardService.swift`:**
```swift
    // Remove copyToClipboard and pasteToActiveApp, replace with:
    
    func insertText(_ text: String, preserveClipboard: Bool) async {
        let trustedCheckOptionPrompt = "AXTrustedCheckOptionPrompt"
        let options = [trustedCheckOptionPrompt: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        
        guard isTrusted else {
            await FileLogger.shared.log("Accessibility permissions missing. Cannot paste automatically.", level: .error)
            if !preserveClipboard {
                // If we can't paste but the user wants it in the clipboard, at least copy it.
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
            return
        }
        
        let pasteboard = NSPasteboard.general
        var backupItems: [NSPasteboardItem]? = nil
        
        // 1. Backup if needed
        if preserveClipboard {
            if let items = pasteboard.pasteboardItems {
                // Deep copy is not strictly necessary for standard types, 
                // but we must create new items to avoid validation errors when re-inserting.
                backupItems = items.compactMap { originalItem in
                    let newItem = NSPasteboardItem()
                    for type in originalItem.types {
                        if let data = originalItem.data(forType: type) {
                            newItem.setData(data, forType: type)
                        }
                    }
                    return newItem
                }
            }
        }
        
        // 2. Set text for pasting
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // 3. Simulate Cmd+V
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s wait before keystroke
        
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode = CGKeyCode(kVK_ANSI_V)
        
        if let eventDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) {
            eventDown.flags = .maskCommand
            eventDown.post(tap: .cghidEventTap)
        }
        
        if let eventUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) {
            eventUp.flags = .maskCommand
            eventUp.post(tap: .cghidEventTap)
        }
        
        await FileLogger.shared.log("Simulated Cmd+V paste event")
        
        // 4. Restore backup if needed
        if preserveClipboard, let backup = backupItems {
            // Wait for the OS to consume the Cmd+V event from the pasteboard.
            // 250ms is usually safe for most Electron/Native apps.
            try? await Task.sleep(nanoseconds: 250_000_000) 
            
            pasteboard.clearContents()
            pasteboard.writeObjects(backup)
            await FileLogger.shared.log("Restored previous clipboard contents")
        } else if !preserveClipboard {
            await FileLogger.shared.log("Copied text to clipboard (permanent)")
        }
    }
```

---

### Task 3: Add Toggle to Menu Bar

**Context:**
- Existing file: `Sources/App/RecodApp.swift` (inside `MenuBarContent`)

**Step 1: Implementation**
- Add a standard SwiftUI `Toggle` connected to `appState.saveToClipboard`.

**Code/Logic changes in `Sources/App/RecodApp.swift` (MenuBarContent view):**
```swift
    var body: some View {
        Button(appState.isRecording ? "Stop Recording" : "Start Recording") {
            appState.toggleRecording()
        }
        .keyboardShortcut("R")

        Divider()
        
        Toggle("Save to Clipboard", isOn: Binding(
            get: { appState.saveToClipboard },
            set: { appState.saveToClipboard = $0 }
        ))
        
        Divider()
// ...
```

---

### Task 4: Add Toggle to General Settings

**Context:**
- Existing file: `Sources/Features/Settings/Views/GeneralSettingsView.swift`

**Step 1: Implementation**
- Add the `saveToClipboard` toggle under the "System" GroupBox, right after the "Record System Audio" toggle.
- Use `StatusToggle` per the design system (`AGENTS.md` Rule 14).

**Code/Logic changes in `Sources/Features/Settings/Views/GeneralSettingsView.swift`:**
```swift
                        // Insert inside the System GroupBox, after "Record System Audio":
                        Divider()

                        HStack {
                            VStack(alignment: .leading) {
                                Text("Save to Clipboard")
                                    .font(.body)
                                Text("Keep transcription in clipboard after pasting")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusToggle(isOn: Binding(
                                get: { appState.saveToClipboard },
                                set: { appState.saveToClipboard = $0 }
                            ))
                        }
```

---

### Task 5: Verification
- Command: `make run`
- Manual Testing:
  1. Copy an image to the clipboard.
  2. Toggle off "Save to Clipboard" in the Menu Bar.
  3. Start recording, say "Hello World", stop.
  4. Verify "Hello World" pastes into the active app.
  5. Press `Cmd+V` again manually — it should paste the *image* you copied earlier.
  6. Toggle "Save to Clipboard" on, record again, paste manually — it should be the text.