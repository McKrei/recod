//
//  SettingsView.swift
//  MacAudio2
//
//  Created for OpenCode.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .scenePadding()
        .frame(width: 500, height: 350)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState // Expecting AppState
    
    var body: some View {
        Form {
            Section("Storage & Debugging") {
                LabeledContent("Recordings") {
                    Button("Reveal in Finder") {
                        appState.revealRecordings()
                    }
                }
                
                LabeledContent("Application Logs") {
                    Button("Open Log File") {
                        appState.revealLogs()
                    }
                }
            }
            
            Section("Shortcuts") {
                LabeledContent("Toggle Recording") {
                    Text("⌘ ⇧ R") // Cmd+Shift+R
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
