//
//  GlassGroupBoxStyle.swift
//  Recod
//
//  Created for OpenCode.
//

import SwiftUI

struct GlassGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            configuration.label
            configuration.content
        }
        .padding(AppTheme.padding)
        .background(AppTheme.glassMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .shadow(color: AppTheme.shadowColor, radius: AppTheme.shadowRadius, x: 0, y: AppTheme.shadowY)
    }
}
