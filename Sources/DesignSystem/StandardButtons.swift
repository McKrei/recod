//
//  StandardButtons.swift
//  Recod
//
//  Created for OpenCode.
//

import SwiftUI

/// A standardized delete button with hover effect.
/// Used in lists and rows for destructive actions.
struct DeleteIconButton: View {
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "trash")
                .font(.system(size: 14))
                .foregroundStyle(isHovering ? .red : .secondary)
                .opacity(isHovering ? 1.0 : 0.7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// A standardized download button.
struct DownloadIconButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 16))
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}

/// A standardized cancel/close button (small xmark).
struct CancelIconButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}
