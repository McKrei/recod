import SwiftUI
import CoreGraphics

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var launchAtLoginService: LaunchAtLoginService
    @State private var showScreenPermissionAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
                    }
                    .padding(8)
                }
                .groupBoxStyle(GlassGroupBoxStyle())

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
    }
}
