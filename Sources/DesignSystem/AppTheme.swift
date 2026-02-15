//
//  AppTheme.swift
//  Recod
//
//  Created for OpenCode.
//

import SwiftUI

enum AppTheme {
    // MARK: - Layout
    
    static let padding: CGFloat = 16
    static let pagePadding: CGFloat = 30
    static let cornerRadius: CGFloat = 16
    static let smallCornerRadius: CGFloat = 8
    static let spacing: CGFloat = 12
    
    // MARK: - Sidebar Layout
    
    static let sidebarWidthExpanded: CGFloat = 200
    static let sidebarWidthCollapsed: CGFloat = 68
    static let sidebarTopSpacing: CGFloat = 20
    static let sidebarButtonBottomSpacing: CGFloat = 24
    
    // MARK: - Styling
    
    static let glassMaterial: Material = .regular
    static let activeMaterial: Material = .thick
    static let inactiveOpacity: CGFloat = 0.6
    static let shadowColor: Color = .black.opacity(0.05)
    static let shadowRadius: CGFloat = 5
    static let shadowY: CGFloat = 2
}
