import Carbon
import AppKit
import Combine

// MARK: - HotKeyManager

/// Manages global hotkey registration using Carbon APIs.
@MainActor
public class HotKeyManager: ObservableObject {
    public static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    public var onTrigger: (() -> Void)?

    @Published public var currentShortcut: HotKeyShortcut

    private static let userDefaultsKey = "hotKeyShortcut"

    private init() {
        // Load saved shortcut or use default
        if let data = UserDefaults.standard.data(forKey: HotKeyManager.userDefaultsKey),
           let shortcut = try? JSONDecoder().decode(HotKeyShortcut.self, from: data) {
            self.currentShortcut = shortcut
        } else {
            self.currentShortcut = .default
        }
    }

    public func registerDefault() {
        register(shortcut: currentShortcut)
    }

    public func register(shortcut: HotKeyShortcut) {
        // Unregister existing hotkey first
        unregister()

        // Save to UserDefaults
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: HotKeyManager.userDefaultsKey)
        }

        currentShortcut = shortcut

        let hotKeyID = EventHotKeyID(signature: 0x4D414341, id: 1) // 'MACA', 1

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Install handler
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handleHotKey()
                return noErr
            },
            1, &eventType, observer, &eventHandler
        )

        // Register the hotkey
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            print("Failed to register hotkey: \(status)")
        } else {
            print("Registered Global Hotkey: \(shortcut.displayString)")
        }
    }

    public func resetToDefault() {
        register(shortcut: .default)
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
