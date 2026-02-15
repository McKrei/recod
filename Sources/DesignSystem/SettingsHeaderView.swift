//
//  SettingsHeaderView.swift
//  Recod
//
//  Created for OpenCode.
//

import SwiftUI

/// A standardized header for settings pages.
/// Displays an icon, title, subtitle description, and an optional trailing action (e.g. Add button).
struct SettingsHeaderView<Action: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: Action

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder action: () -> Action = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.action = action()
    }

    var body: some View {
        GroupBox {
            HStack(spacing: AppTheme.padding) {
                Image(systemName: systemImage)
                    .font(.system(size: AppTheme.headerIconSize))
                    .foregroundStyle(.primary)
                    .frame(width: AppTheme.headerIconFrameWidth)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                action
            }
            .padding(8)
        }
        .groupBoxStyle(GlassGroupBoxStyle())
    }
}

#Preview {
    VStack(spacing: 20) {
        SettingsHeaderView(
            title: "Example Settings",
            subtitle: "This is a standardized header component.",
            systemImage: "gear"
        )

        SettingsHeaderView(
            title: "With Action",
            subtitle: "Header with a trailing button.",
            systemImage: "plus.circle"
        ) {
            Button("Add") {}
                .buttonStyle(.bordered)
        }
    }
    .padding()
    .frame(width: 500)
    .background(Color.gray.opacity(0.1))
}
