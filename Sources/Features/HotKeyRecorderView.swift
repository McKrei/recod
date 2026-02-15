//
//  HotKeyRecorderView.swift
//  MacAudio2
//
//  Created for OpenCode.
//

import SwiftUI
import AppKit
import Carbon

// MARK: - HotKeyRecorderView

struct HotKeyRecorderView: View {
    @ObservedObject var hotKeyManager = HotKeyManager.shared
    @State private var isRecording = false
    @State private var pendingModifiers: NSEvent.ModifierFlags = []
    @State private var keyMonitor: Any?
    @State private var flagsMonitor: Any?

    var body: some View {
        HStack(spacing: 12) {
            // Main button — click to record
            Button {
                if isRecording {
                    cancelRecording()
                } else {
                    startRecording()
                }
            } label: {
                Group {
                    if isRecording {
                        recordingLabel
                    } else {
                        shortcutLabel
                    }
                }
                .frame(minWidth: 120, minHeight: 32)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isRecording ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isRecording ? Color.accentColor : Color.white.opacity(0.15),
                            lineWidth: isRecording ? 2 : 1
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Reset button
            if hotKeyManager.currentShortcut != .default {
                Button {
                    hotKeyManager.resetToDefault()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.white.opacity(0.15), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Reset to ⌘⇧R")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: hotKeyManager.currentShortcut)
        .animation(.spring(duration: 0.3), value: isRecording)
        .onDisappear {
            cancelRecording()
        }
    }

    // MARK: - Sub-views

    private var recordingLabel: some View {
        HStack(spacing: 6) {
            if !pendingModifiers.isEmpty {
                ForEach(modifierSymbols(for: pendingModifiers), id: \.self) { symbol in
                    KeyView(symbol: symbol)
                }
                Text("+ ...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("Press shortcut...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var shortcutLabel: some View {
        HStack(spacing: 4) {
            ForEach(hotKeyManager.currentShortcut.modifierSymbols, id: \.self) { symbol in
                KeyView(symbol: symbol)
            }
            KeyView(text: hotKeyManager.currentShortcut.keyName)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Recording Logic

    private func startRecording() {
        guard !isRecording else { return }

        // Unregister current hotkey so it doesn't fire during recording
        HotKeyManager.shared.unregister()

        // CRITICAL: Make the app a "regular" app so it can receive keyboard focus
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Ensure the settings window becomes key
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
        }

        isRecording = true
        pendingModifiers = []

        // Monitor key presses
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = event.keyCode

            // Escape cancels recording
            if code == UInt16(kVK_Escape) {
                cancelRecording()
                return nil
            }

            let cocoaModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let carbonMods = HotKeyShortcut.carbonModifiers(from: cocoaModifiers)

            // Require at least one modifier (except for F-keys which can be solo)
            let isFKey = (code >= UInt16(kVK_F1) && code <= UInt16(kVK_F12))
                || code == UInt16(kVK_F13) || code == UInt16(kVK_F14)
                || code == UInt16(kVK_F15) || code == UInt16(kVK_F16)

            guard carbonMods != 0 || isFKey else {
                return nil
            }

            let shortcut = HotKeyShortcut(
                keyCode: UInt32(code),
                modifiers: carbonMods
            )

            finishRecording(with: shortcut)
            return nil
        }

        // Monitor modifier flag changes for live preview
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let cocoaModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            pendingModifiers = cocoaModifiers
            return nil
        }
    }

    private func finishRecording(with shortcut: HotKeyShortcut) {
        removeMonitors()
        isRecording = false
        pendingModifiers = []

        // Register new shortcut
        HotKeyManager.shared.register(shortcut: shortcut)

        // Return to accessory mode (menu bar app)
        NSApp.setActivationPolicy(.accessory)
    }

    private func cancelRecording() {
        removeMonitors()
        isRecording = false
        pendingModifiers = []

        // Re-register the previous hotkey
        HotKeyManager.shared.registerDefault()

        // Return to accessory mode
        NSApp.setActivationPolicy(.accessory)
    }

    private func removeMonitors() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
    }

    // MARK: - Helpers

    private func modifierSymbols(for flags: NSEvent.ModifierFlags) -> [String] {
        var symbols: [String] = []
        if flags.contains(.control) { symbols.append("⌃") }
        if flags.contains(.option) { symbols.append("⌥") }
        if flags.contains(.shift) { symbols.append("⇧") }
        if flags.contains(.command) { symbols.append("⌘") }
        return symbols
    }
}
