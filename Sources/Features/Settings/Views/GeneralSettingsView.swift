import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var launchAtLoginService: LaunchAtLoginService

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
                            StatusToggle(isOn: $appState.recordSystemAudio)
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
    }
}
