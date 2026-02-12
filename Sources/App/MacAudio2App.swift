//
//  MacAudio2App.swift
//  MacAudio2
//
//  Created for OpenCode.
//

import SwiftUI
import AppKit
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var overlayWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupOverlayWindow()
        
        // Observe AppState
        Task { @MainActor in
            AppState.shared.$isOverlayVisible
                .sink { [weak self] visible in
                    if visible {
                        self?.showOverlay()
                    } else {
                        self?.hideOverlay()
                    }
                }
                .store(in: &cancellables)
        }
    }
    
    private func setupOverlayWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        window.isReleasedWhenClosed = false
        
        // Center horizontally, position at bottom
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let windowRect = window.frame
            let x = screenRect.midX - (windowRect.width / 2)
            let y = screenRect.minY + 80 // 80px from bottom
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        let hostingView = NSHostingView(rootView: OverlayView(appState: AppState.shared))
        hostingView.sizingOptions = .intrinsicContentSize
        window.contentView = hostingView
        
        self.overlayWindow = window
    }
    
    private func showOverlay() {
        overlayWindow?.makeKeyAndOrderFront(nil)
    }
    
    private func hideOverlay() {
        overlayWindow?.orderOut(nil)
    }
    
    // Helper to bring Settings to front
    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct MacAudio2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    
    var body: some Scene {
        MenuBarExtra("MacAudio2", systemImage: appState.isRecording ? "record.circle.fill" : "mic.circle") {
            Button(appState.isRecording ? "Stop Recording" : "Start Recording") {
                appState.toggleRecording()
            }
            .keyboardShortcut("R")
            
            Divider()
            
            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("Q")
        }
        .menuBarExtraStyle(.menu)
        
        Settings {
            SettingsView()
                .environmentObject(appState)
                .onAppear {
                    appDelegate.showSettings()
                }
        }
    }
}
