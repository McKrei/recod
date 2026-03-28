import SwiftUI
import CoreGraphics
import AppKit

struct GeneralSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var launchAtLoginService: LaunchAtLoginService
    @State private var showScreenPermissionAlert = false

    @State private var importSummary: ImportSummary?
    @State private var showImportAlert = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    private var recordSystemAudioBinding: Binding<Bool> {
        Binding(
            get: { appState.recordSystemAudio },
            set: { newValue in
                if newValue && !CGPreflightScreenCaptureAccess() {
                    CGRequestScreenCaptureAccess()
                    showScreenPermissionAlert = true
                }
                appState.recordSystemAudio = newValue
            }
        )
    }

    private var saveToClipboardBinding: Binding<Bool> {
        Binding(
            get: { appState.saveToClipboard },
            set: { appState.saveToClipboard = $0 }
        )
    }

    private var escapeCancelsRecordingBinding: Binding<Bool> {
        Binding(
            get: { appState.escapeCancelsRecording },
            set: { appState.escapeCancelsRecording = $0 }
        )
    }

    var body: some View {
        SettingsPageContainer(
            title: "General Settings",
            subtitle: "Manage storage, startup behavior, shortcuts, and data portability.",
            systemImage: "gearshape"
        ) {
            storageSection
            systemSection
            shortcutsSection
            backupSection
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
        SettingsSectionCard(
            title: "Storage & Debugging",
            systemImage: "externaldrive"
        ) {
            SettingsActionRow(
                title: "Recordings",
                subtitle: "Manage your audio files"
            ) {
                Button("Reveal in Finder") {
                    appState.revealRecordings()
                }
                .buttonStyle(.bordered)
            }

            Divider()

            SettingsActionRow(
                title: "Logs",
                subtitle: "View application logs"
            ) {
                Button("Open Log File") {
                    appState.revealLogs()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var systemSection: some View {
        SettingsSectionCard(
            title: "System",
            systemImage: "macwindow"
        ) {
            SettingsToggleRow(
                title: "Launch at Login",
                subtitle: "Automatically start Recod when you log in",
                isOn: $launchAtLoginService.isEnabled
            )

            Divider()

            SettingsToggleRow(
                title: "Record System Audio",
                subtitle: "Include computer sound (stereo split)",
                isOn: recordSystemAudioBinding
            )

            Divider()

            SettingsToggleRow(
                title: "Save to Clipboard",
                subtitle: "Keep transcription in clipboard after pasting",
                isOn: saveToClipboardBinding
            )

            Divider()

            SettingsToggleRow(
                title: "Escape Cancels Recording",
                subtitle: "Press Esc to abort recording without saving or transcribing",
                isOn: escapeCancelsRecordingBinding
            )
        }
    }

    private var shortcutsSection: some View {
        SettingsSectionCard(
            title: "Shortcuts",
            systemImage: "keyboard"
        ) {
            SettingsActionRow(
                title: "Toggle Recording",
                subtitle: "Capture or stop audio with a global shortcut"
            ) {
                HotKeyRecorderView()
            }
        }
    }

    private var backupSection: some View {
        SettingsSectionCard(
            title: "Data Backup",
            systemImage: "arrow.triangle.2.circlepath"
        ) {
            SettingsActionRow(
                title: "Export Data",
                subtitle: "Save transcriptions, post-processing results, dictionary, and actions (without API keys)"
            ) {
                Button("Export...") {
                    exportData()
                }
                .buttonStyle(.bordered)
            }

            Divider()

            SettingsActionRow(
                title: "Import Data",
                subtitle: "Restore transcriptions, post-processing results, dictionary, and actions (without API keys)"
            ) {
                Button("Import...") {
                    importData()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Backup Actions

    @MainActor
    private func exportData() {
        let suggestedFileName = "Recod_Backup_\(Date().formatted(.iso8601.year().month().day())).json"
        if let url = FilePanelService.chooseJSONSaveURL(
            suggestedFileName: suggestedFileName,
            title: "Export Data",
            prompt: "Export"
        ) {
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
        if let url = FilePanelService.chooseJSONOpenURL(title: "Import Data", prompt: "Import") {
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
