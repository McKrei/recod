//
//  SettingsView.swift
//  Recod
//
//  Created for OpenCode.
//

import SwiftUI
import SwiftData

// MARK: - Models

enum SettingsSelection: Hashable, Identifiable, CaseIterable {
    case general
    case models
    case replacements
    case history

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .models: return "Models"
        case .replacements: return "Replacements"
        case .history: return "History"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .models: return "cpu"
        case .replacements: return "text.badge.checkmark"
        case .history: return "clock"
        }
    }
}

// MARK: - Main View

struct SettingsView: View {
    @State private var selection: SettingsSelection? = .general
    @State private var isExpanded: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            SidebarView(selection: $selection, isExpanded: $isExpanded)
                .zIndex(1)

            // Divider
            Rectangle()
                .fill(Color.primary.opacity(0.2))
                .frame(width: 1)
                .ignoresSafeArea()

            // Content
            ZStack {
                if let selection {
                    switch selection {
                    case .general:
                        GeneralSettingsView()
                    case .models:
                        ModelsSettingsView()
                    case .replacements:
                        ReplacementsSettingsView()
                    case .history:
                        HistoryView()
                    }
                } else {
                    ContentUnavailableView("Select a setting", systemImage: "gear")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
        }
        .frame(width: 800, height: 500)
        .background(WindowAccessor { window in
            // Clear the window background to allow pure custom material
            window.isOpaque = false
            window.backgroundColor = .clear

            // Hide title bar but keep buttons
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)

            // Enable dragging by background
            window.isMovableByWindowBackground = true

            // Ensure shadow
            window.hasShadow = true

            // Window Buttons: Hide Zoom (Green), keep others
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
            window.standardWindowButton(.closeButton)?.isHidden = false
        })
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environment(AudioPlayer())
        .modelContainer(for: Recording.self, inMemory: true)
}
