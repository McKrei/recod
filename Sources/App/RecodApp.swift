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
import Carbon

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var overlayWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupOverlayWindow()
        setupSignalHandlers()
        setupEscapeCancellationMonitoring()

        // Prepare audio engine at launch: request permission, align sample rates, build graph.
        // The engine stays running idle so the first recording starts immediately without a cold-start delay.
        AppState.shared.prepareAudio()

        // Observe AppState
        Task { @MainActor in
            OverlayState.shared.$isVisible
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

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
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

    private func setupEscapeCancellationMonitoring() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            guard !event.isARepeat else { return nil }
            guard AppState.shared.escapeCancelsRecording else { return event }
            guard RecordingOrchestrator.shared.isRecording else { return event }

            RecordingOrchestrator.shared.cancelCurrentRecording()
            return nil
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            guard !event.isARepeat else { return }

            Task { @MainActor in
                guard AppState.shared.escapeCancelsRecording else { return }
                guard RecordingOrchestrator.shared.isRecording else { return }
                RecordingOrchestrator.shared.cancelCurrentRecording()
            }
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

        let hostingView = NSHostingView(rootView: OverlayView())
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
        Button("Settings...") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Toggle("Save to Clipboard", isOn: Binding(
            get: { appState.saveToClipboard },
            set: { appState.saveToClipboard = $0 }
        ))

        Divider()

        Button("Check for Updates...") {
            updaterManager.checkForUpdates()
        }
        .disabled(!updaterManager.canCheckForUpdates)

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}

@main
struct RecodApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var orchestrator = RecordingOrchestrator.shared
    @StateObject private var updaterManager = UpdaterManager()
    @StateObject private var launchAtLoginService = LaunchAtLoginService()
    @State private var audioPlayer = AudioPlayer()

    let modelContainer: ModelContainer

    init() {
        Self.backupDatabase()

        do {
            modelContainer = try ModelContainer(for: Recording.self, ReplacementRule.self, PostProcessingAction.self)
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
        MenuBarExtra {
            MenuBarContent(appState: appState, updaterManager: updaterManager)
                .modelContainer(modelContainer)
                .environment(audioPlayer)
        } label: {
            // Change pointSize value to adjust icon size (e.g. 20)
            let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
            let image = NSImage(
                systemSymbolName: orchestrator.isRecording ? "record.circle.fill" : "mic.circle",
                accessibilityDescription: nil
            )?.withSymbolConfiguration(config)

            Image(nsImage: image ?? NSImage())
        }
        .menuBarExtraStyle(.menu)

        WindowGroup(id: "settings") {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(launchAtLoginService)
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
