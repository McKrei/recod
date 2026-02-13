//
//  GlassRowStyle.swift
//  MacAudio2
//
//  Created for OpenCode.
//

import SwiftUI

/// A reusable modifier for list rows that follow the "Tahoe" glass design.
/// Applies padding, background material, corner radius, shadow, and optional hover/selection states.
struct GlassRowModifier: ViewModifier {
    var isSelected: Bool
    var isHovering: Bool
    
    func body(content: Content) -> some View {
        content
            .padding(AppTheme.padding)
            .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.1)) : AnyShapeStyle(AppTheme.glassMaterial))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .shadow(color: AppTheme.shadowColor, radius: AppTheme.shadowRadius, x: 0, y: AppTheme.shadowY)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.5) : Color.white.opacity(isHovering ? 0.2 : 0),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
    }
}

extension View {
    /// Applies the standard glass row styling.
    /// - Parameters:
    ///   - isSelected: Whether the row is currently selected (adds tint and border).
    ///   - isHovering: Whether the row is being hovered (adds subtle border).
    func glassRowStyle(isSelected: Bool = false, isHovering: Bool = false) -> some View {
        modifier(GlassRowModifier(isSelected: isSelected, isHovering: isHovering))
    }
}
