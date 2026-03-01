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
        Task { await FileLogger.shared.log("Copied text to clipboard (manual copy)") }
    }
    
    func insertText(_ text: String, preserveClipboard: Bool) async {
        let trustedCheckOptionPrompt = "AXTrustedCheckOptionPrompt"
        let options = [trustedCheckOptionPrompt: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        
        guard isTrusted else {
            Task { await FileLogger.shared.log("Accessibility permissions missing. Cannot paste automatically.", level: .error) }
            if preserveClipboard == false {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
            return
        }
        
        let pasteboard = NSPasteboard.general
        var backupItems: [NSPasteboardItem]? = nil
        
        if preserveClipboard {
            if let items = pasteboard.pasteboardItems {
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
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
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
        
        Task { await FileLogger.shared.log("Simulated Cmd+V paste event") }
        
        if preserveClipboard, let backup = backupItems {
            try? await Task.sleep(nanoseconds: 250_000_000)
            
            pasteboard.clearContents()
            pasteboard.writeObjects(backup)
            Task { await FileLogger.shared.log("Restored previous clipboard contents") }
        } else if !preserveClipboard {
            Task { await FileLogger.shared.log("Copied text to clipboard (permanent)") }
        }
    }
}
