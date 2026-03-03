import Testing
import Foundation
import Carbon
import AppKit
@testable import Recod

@Suite("HotKeyShortcut")
struct HotKeyShortcutTests {
    
    // MARK: - carbonModifiers(from:) Tests
    
    @Test("carbonModifiers: NSEvent.ModifierFlags.command to cmdKey")
    func carbonModifiersCommand() {
        let flags = NSEvent.ModifierFlags.command
        #expect(HotKeyShortcut.carbonModifiers(from: flags) == UInt32(cmdKey))
    }
    
    @Test("carbonModifiers: NSEvent.ModifierFlags.shift to shiftKey")
    func carbonModifiersShift() {
        let flags = NSEvent.ModifierFlags.shift
        #expect(HotKeyShortcut.carbonModifiers(from: flags) == UInt32(shiftKey))
    }
    
    @Test("carbonModifiers: NSEvent.ModifierFlags.option to optionKey")
    func carbonModifiersOption() {
        let flags = NSEvent.ModifierFlags.option
        #expect(HotKeyShortcut.carbonModifiers(from: flags) == UInt32(optionKey))
    }
    
    @Test("carbonModifiers: NSEvent.ModifierFlags.control to controlKey")
    func carbonModifiersControl() {
        let flags = NSEvent.ModifierFlags.control
        #expect(HotKeyShortcut.carbonModifiers(from: flags) == UInt32(controlKey))
    }
    
    @Test("carbonModifiers: Combined modifiers")
    func carbonModifiersCombined() {
        let flags: NSEvent.ModifierFlags = [.command, .shift]
        let expected = UInt32(cmdKey | shiftKey)
        #expect(HotKeyShortcut.carbonModifiers(from: flags) == expected)
    }
    
    @Test("carbonModifiers: All four modifiers")
    func carbonModifiersAllFour() {
        let flags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let expected = UInt32(cmdKey | shiftKey | optionKey | controlKey)
        #expect(HotKeyShortcut.carbonModifiers(from: flags) == expected)
    }
    
    @Test("carbonModifiers: Empty flags returns 0")
    func carbonModifiersEmpty() {
        #expect(HotKeyShortcut.carbonModifiers(from: []) == 0)
    }
    
    // MARK: - displayString Tests
    
    @Test("displayString: Default shortcut is ⇧⌘R")
    func displayStringDefault() {
        let shortcut = HotKeyShortcut.default
        #expect(shortcut.displayString == "⇧⌘R")
    }
    
    @Test("displayString: All modifiers")
    func displayStringAllModifiers() {
        let shortcut = HotKeyShortcut(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
        )
        // Order: ⌃ ⌥ ⇧ ⌘
        #expect(shortcut.displayString == "⌃⌥⇧⌘A")
    }
    
    @Test("displayString: No modifiers")
    func displayStringNoModifiers() {
        let shortcut = HotKeyShortcut(keyCode: UInt32(kVK_F5), modifiers: 0)
        #expect(shortcut.displayString == "F5")
    }
    
    @Test("displayString: Space key")
    func displayStringSpaceKey() {
        let shortcut = HotKeyShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
        #expect(shortcut.displayString == "⌘Space")
    }
    
    // MARK: - modifierSymbols Tests
    
    @Test("modifierSymbols: Default")
    func modifierSymbolsDefault() {
        let symbols = HotKeyShortcut.default.modifierSymbols
        #expect(symbols == ["⇧", "⌘"])
    }
    
    @Test("modifierSymbols: Empty")
    func modifierSymbolsEmpty() {
        let shortcut = HotKeyShortcut(keyCode: UInt32(kVK_F1), modifiers: 0)
        #expect(shortcut.modifierSymbols == [])
    }
    
    @Test("modifierSymbols: Specific order (macOS standard)")
    func modifierSymbolsOrder() {
        let shortcut = HotKeyShortcut(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
        )
        #expect(shortcut.modifierSymbols == ["⌃", "⌥", "⇧", "⌘"])
    }
    
    // MARK: - keyName Tests
    
    @Test("keyName: Letters")
    func keyNameLetters() {
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: 0).keyName == "A")
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_ANSI_Z), modifiers: 0).keyName == "Z")
    }
    
    @Test("keyName: Digits")
    func keyNameDigits() {
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_ANSI_0), modifiers: 0).keyName == "0")
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_ANSI_9), modifiers: 0).keyName == "9")
    }
    
    @Test("keyName: Function keys")
    func keyNameFunctionKeys() {
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_F1), modifiers: 0).keyName == "F1")
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_F12), modifiers: 0).keyName == "F12")
    }
    
    @Test("keyName: Special keys")
    func keyNameSpecialKeys() {
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_Return), modifiers: 0).keyName == "↩")
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_Space), modifiers: 0).keyName == "Space")
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_Escape), modifiers: 0).keyName == "⎋")
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_Delete), modifiers: 0).keyName == "⌫")
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_Tab), modifiers: 0).keyName == "⇥")
    }
    
    @Test("keyName: Arrows")
    func keyNameArrows() {
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: 0).keyName == "←")
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_RightArrow), modifiers: 0).keyName == "→")
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_UpArrow), modifiers: 0).keyName == "↑")
        #expect(HotKeyShortcut(keyCode: UInt32(kVK_DownArrow), modifiers: 0).keyName == "↓")
    }
    
    @Test("keyName: Unknown code")
    func keyNameUnknown() {
        #expect(HotKeyShortcut(keyCode: 999, modifiers: 0).keyName == "?")
    }
    
    // MARK: - Codable & Equatable Tests
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = HotKeyShortcut.default
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotKeyShortcut.self, from: data)
        #expect(decoded == original)
    }
    
    @Test("Equatable: Same key code and modifiers are equal")
    func equatableSame() {
        let s1 = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey))
        let s2 = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey))
        #expect(s1 == s2)
    }
    
    @Test("Equatable: Different key code are not equal")
    func equatableDifferentKey() {
        let s1 = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey))
        let s2 = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey))
        #expect(s1 != s2)
    }
    
    @Test("Equatable: Different modifiers are not equal")
    func equatableDifferentModifiers() {
        let s1 = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey))
        let s2 = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(shiftKey))
        #expect(s1 != s2)
    }
}
