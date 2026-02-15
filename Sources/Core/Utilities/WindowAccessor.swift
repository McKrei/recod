//
//  WindowAccessor.swift
//  Recod
//
//  Created for OpenCode.
//

import SwiftUI
import AppKit

/// A view that accesses the underlying NSWindow and configures it.
struct WindowAccessor: NSViewRepresentable {
    let config: (NSWindow) -> Void
    
    init(_ config: @escaping (NSWindow) -> Void) {
        self.config = config
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Wait for next runloop tick to ensure window is attached
        DispatchQueue.main.async {
            if let window = view.window {
                config(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                config(window)
            }
        }
    }
}
