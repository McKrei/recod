//
//  HotKeyManager.swift
//  MacAudio2
//
//  Created for OpenCode.
//

import Carbon
import AppKit

/// Manages global hotkey registration using Carbon APIs.
@MainActor
public class HotKeyManager {
    public static let shared = HotKeyManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    public var onTrigger: (() -> Void)?
    
    private init() {}
    
    public func registerDefault() {
        // Cmd+Shift+R
        // Cmd = cmdKey (0x0100) | shiftKey (0x0200) -> 55 (Command) is modifier?
        // Let's use standard modifiers.
        // kVK_ANSI_R = 0x0F (15)
        
        let hotKeyID = EventHotKeyID(signature: 0x4D414341, id: 1) // 'MACA', 1
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        // Install handler
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        InstallEventHandler(GetApplicationEventTarget(), { (handler, event, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            
            manager.handleHotKey()
            
            return noErr
        }, 1, &eventType, observer, &eventHandler)
        
        // Register HotKey (Cmd+Shift+R)
        // R = 15
        // Cmd = cmdKey
        // Shift = shiftKey
        let modifiers = cmdKey | shiftKey
        
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        if status != noErr {
            print("Failed to register hotkey: \(status)")
        } else {
            print("Registered Global Hotkey: Cmd+Shift+R")
        }
    }
    
    public func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
    
    private func handleHotKey() {
        Task { @MainActor in
            self.onTrigger?()
        }
    }
}
