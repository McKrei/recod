import SwiftUI
import CoreGraphics
import AppKit

struct GeneralSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var launchAtLoginService: LaunchAtLoginService
    @State private var showScreenPermissionAlert = false
    
    // Backup State
    @State private var importSummary: ImportSummary?
    @State private var showImportAlert = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                storageSection
                systemSection
                shortcutsSection
                backupSection
            }
            .padding(30)
        }
        .alert("Screen Recording Permission Required", isPresented: $showScreenPermissionAlert) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {
                appState.recordSystemAudio = false
            }
        } message: {
            Text("To record system audio, please enable Screen & System Audio Recording for Recod in System Settings → Privacy & Security.\n\nAfter enabling, restart the app.")
        }
        .alert("Import Summary", isPresented: $showImportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let summary = importSummary {
                Text("""
                Import completed successfully.
                
                Transcriptions:
                - Imported: \(summary.recordingsImported)
                - Skipped (Duplicates): \(summary.recordingsSkipped)
                
                Dictionary Rules:
                - Imported: \(summary.rulesImported)
                - Skipped (Duplicates): \(summary.rulesSkipped)

                Post-Processing Actions:
                - Imported: \(summary.actionsImported)
                - Skipped (Duplicates): \(summary.actionsSkipped)

                Custom Providers (without API keys):
                - Imported: \(summary.customProvidersImported)
                """)
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }
    
    // MARK: - Sections
    
    private var storageSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("Storage & Debugging", systemImage: "externaldrive")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Divider()

                HStack {
                    VStack(alignment: .leading) {
                        Text("Recordings")
                            .font(.body)
                        Text("Manage your audio files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reveal in Finder") {
                        appState.revealRecordings()
                    }
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text("Logs")
                            .font(.body)
                        Text("View application logs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Log File") {
                        appState.revealLogs()
                    }
                }
            }
            .padding(8)
        }
        .groupBoxStyle(GlassGroupBoxStyle())
    }
    
    private var systemSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("System", systemImage: "macwindow")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Divider()

                HStack {
                    VStack(alignment: .leading) {
                        Text("Launch at Login")
                            .font(.body)
                        Text("Automatically start Recod when you log in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusToggle(isOn: $launchAtLoginService.isEnabled)
                }

                Divider()

                HStack {
                    VStack(alignment: .leading) {
                        Text("Record System Audio")
                            .font(.body)
                        Text("Include computer sound (stereo split)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusToggle(isOn: Binding(
                        get: { appState.recordSystemAudio },
                        set: { newValue in
                            if newValue {
                                // Check if screen capture permission is granted
                                if !CGPreflightScreenCaptureAccess() {
                                    // Request permission (opens System Settings)
                                    CGRequestScreenCaptureAccess()
                                    showScreenPermissionAlert = true
                                }
                            }
                            appState.recordSystemAudio = newValue
                        }
                    ))
                }

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

                Divider()

                HStack {
                    VStack(alignment: .leading) {
                        Text("Escape Cancels Recording")
                            .font(.body)
                        Text("Press Esc to abort recording without saving or transcribing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusToggle(isOn: Binding(
                        get: { appState.escapeCancelsRecording },
                        set: { appState.escapeCancelsRecording = $0 }
                    ))
                }
            }
            .padding(8)
        }
        .groupBoxStyle(GlassGroupBoxStyle())
    }
    
    private var shortcutsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("Shortcuts", systemImage: "keyboard")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Divider()

                HStack {
                    Text("Toggle Recording")
                    Spacer()
                    HotKeyRecorderView()
                }
            }
            .padding(8)
        }
        .groupBoxStyle(GlassGroupBoxStyle())
    }
    
    private var backupSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("Data Backup", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Divider()

                HStack {
                    VStack(alignment: .leading) {
                        Text("Export Data")
                            .font(.body)
                        Text("Save transcriptions, post-processing results, dictionary, and actions (without API keys)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Export...") {
                        exportData()
                    }
                }

                Divider()

                HStack {
                    VStack(alignment: .leading) {
                        Text("Import Data")
                            .font(.body)
                        Text("Restore transcriptions, post-processing results, dictionary, and actions (without API keys)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Import...") {
                        importData()
                    }
                }
            }
            .padding(8)
        }
        .groupBoxStyle(GlassGroupBoxStyle())
    }
    
    // MARK: - Backup Actions
    
    @MainActor
    private func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Recod_Backup_\(Date().formatted(.iso8601.year().month().day())).json"
        panel.title = "Export Data"
        panel.prompt = "Export"
        
        // Ensure app can present modal panels over other apps
        NSApp.activate(ignoringOtherApps: true)
        
        // Show panel synchronously. In SwiftUI menu bar apps, this is sometimes required 
        // to prevent the panel from silently failing to appear in the background.
        let response = panel.runModal()
        
        if response == .OK, let url = panel.url {
            do {
                let data = try DataBackupService.shared.exportData(context: modelContext)
                try data.write(to: url)
            } catch {
                self.errorMessage = error.localizedDescription
                self.showErrorAlert = true
            }
        }
    }

    @MainActor
    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Data"
        panel.prompt = "Import"
        
        // Ensure app can present modal panels over other apps
        NSApp.activate(ignoringOtherApps: true)
        
        let response = panel.runModal()
        
        if response == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let summary = try DataBackupService.shared.importData(from: data, context: modelContext)
                self.importSummary = summary
                self.showImportAlert = true
            } catch {
                self.errorMessage = error.localizedDescription
                self.showErrorAlert = true
            }
        }
    }
}
