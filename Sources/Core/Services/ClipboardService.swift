import AppKit
import ApplicationServices
import Carbon

@MainActor
final class ClipboardService {
    static let shared = ClipboardService()
    
    private init() {}
    
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Task { await FileLogger.shared.log("Copied text to clipboard") }
    }
    
    nonisolated func pasteToActiveApp() {
        let trustedCheckOptionPrompt = "AXTrustedCheckOptionPrompt"
        let options = [trustedCheckOptionPrompt: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        
        guard isTrusted else {
            Task { await FileLogger.shared.log("Accessibility permissions missing. Cannot paste automatically.", level: .error) }
            return
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            
            let source = CGEventSource(stateID: .hidSystemState)
            let vKeyCode = CGKeyCode(kVK_ANSI_V)
            
            guard let eventDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else { return }
            eventDown.flags = .maskCommand
            eventDown.post(tap: .cghidEventTap)
            
            guard let eventUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else { return }
            eventUp.flags = .maskCommand
            eventUp.post(tap: .cghidEventTap)
            
            await FileLogger.shared.log("Simulated Cmd+V paste event")
        }
    }
}
