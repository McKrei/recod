//
//  RecodApp.swift
//  Recod
//
//  Created for OpenCode.
//

import SwiftUI
import AppKit
import Combine
import SwiftData

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var overlayWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupOverlayWindow()
        setupSignalHandlers()

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

    private func setupSignalHandlers() {
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler {
            NSApplication.shared.terminate(nil)
        }
        sigintSource.resume()

        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigtermSource.setEventHandler {
            NSApplication.shared.terminate(nil)
        }
        sigtermSource.resume()

        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
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

struct MenuBarContent: View {
    @ObservedObject var appState: AppState
    @ObservedObject var updaterManager: UpdaterManager
    @Environment(\.openWindow) var openWindow

    var body: some View {
        Button(appState.isRecording ? "Stop Recording" : "Start Recording") {
            appState.toggleRecording()
        }
        .keyboardShortcut("R")

        Divider()

        Button("Check for Updates...") {
            updaterManager.checkForUpdates()
        }
        .disabled(!updaterManager.canCheckForUpdates)

        Button("Settings...") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("Q")
    }
}

@main
struct RecodApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var updaterManager = UpdaterManager()
    @State private var audioPlayer = AudioPlayer()

    let modelContainer: ModelContainer

    init() {
        Self.backupDatabase()

        do {
            modelContainer = try ModelContainer(for: Recording.self)
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }

        let container = modelContainer
        Task { @MainActor in
            // Inject ModelContext into AppState for reactive updates
            AppState.shared.modelContext = container.mainContext

            await RecordingSyncService().syncRecordings(modelContext: container.mainContext)
        }
    }

    var body: some Scene {
        MenuBarExtra("Recod", systemImage: appState.isRecording ? "record.circle.fill" : "mic.circle") {
            MenuBarContent(appState: appState, updaterManager: updaterManager)
                .modelContainer(modelContainer)
                .environment(audioPlayer)
        }
        .menuBarExtraStyle(.menu)

        WindowGroup(id: "settings") {
            SettingsView()
                .environmentObject(appState)
                .environment(audioPlayer)
                .modelContainer(modelContainer)
                .background(WindowAccessor { window in
                    window.makeKeyAndOrderFront(nil)
                })
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }

    /// Creates a backup of the default.store file if it exists.
    /// This is a safety measure before SwiftData performs any migrations.
    private static func backupDatabase() {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }

        let storeURL = appSupportURL.appendingPathComponent("default.store")
        let shmURL = appSupportURL.appendingPathComponent("default.store-shm")
        let walURL = appSupportURL.appendingPathComponent("default.store-wal")

        let backupExtension = ".bak"

        let filesToBackup = [storeURL, shmURL, walURL]

        for url in filesToBackup {
            if fileManager.fileExists(atPath: url.path) {
                let backupURL = url.appendingPathExtension(backupExtension)
                do {
                    if fileManager.fileExists(atPath: backupURL.path) {
                        try fileManager.removeItem(at: backupURL)
                    }
                    try fileManager.copyItem(at: url, to: backupURL)
                    print("Backed up \(url.lastPathComponent) to \(backupURL.lastPathComponent)")
                } catch {
                    print("Failed to backup \(url.lastPathComponent): \(error)")
                }
            }
        }
    }
}
