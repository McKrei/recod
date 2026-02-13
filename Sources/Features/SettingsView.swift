//
//  SettingsView.swift
//  MacAudio2
//
//  Created for OpenCode.
//

import SwiftUI
import SwiftData

// MARK: - Models

enum SettingsSelection: Hashable, Identifiable, CaseIterable {
    case general
    case history

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .history: return "History"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
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

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selection: SettingsSelection?
    @Binding var isExpanded: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top spacing for traffic lights (approx 28pt standard)
            Color.clear.frame(height: AppTheme.sidebarTopSpacing)
            
            // Toggle Button (Moved to top)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "sidebar.left" : "sidebar.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
            .padding(.leading, isExpanded ? 16 : 0)
            .padding(.bottom, AppTheme.sidebarButtonBottomSpacing)
            
            // Navigation Items
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(SettingsSelection.allCases) { item in
                        SidebarItem(
                            item: item,
                            isSelected: selection == item,
                            isExpanded: isExpanded
                        ) {
                            selection = item
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            
            Spacer()
        }
        .frame(width: isExpanded ? AppTheme.sidebarWidthExpanded : AppTheme.sidebarWidthCollapsed)
        .background(.ultraThinMaterial)
    }
}

struct SidebarItem: View {
    let item: SettingsSelection
    let isSelected: Bool
    let isExpanded: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                
                if isExpanded {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.title)
    }
}
// MARK: - Content Views

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    
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
                        Label("Shortcuts", systemImage: "keyboard")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        Divider()
                        
                        HStack {
                            Text("Toggle Recording")
                            Spacer()
                            HStack(spacing: 4) {
                                KeyView(symbol: "⌘")
                                KeyView(symbol: "⇧")
                                KeyView(text: "R")
                            }
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

struct KeyView: View {
    var symbol: String?
    var text: String?
    
    var body: some View {
        Text(symbol ?? text ?? "")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(minWidth: 24, minHeight: 24)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Material.thick)
                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            )
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environment(AudioPlayer())
        .modelContainer(for: Recording.self, inMemory: true)
}
