//
//  OverlayView.swift
//  MacAudio2
//
//  Created for OpenCode.
//

import SwiftUI

struct OverlayView: View {
    @ObservedObject var appState: AppState // Receive real app state
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 56, height: 56)
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)

            Circle()
                .stroke(.red.opacity(0.6), lineWidth: 2)
                .frame(width: 20, height: 20)
                .scaleEffect(isAnimating ? 2.2 : 1.0)
                .opacity(isAnimating ? 0 : 1)
                .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: isAnimating)

            Image(systemName: "mic.fill")
                .font(.system(size: 20))
                .foregroundStyle(.red)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    OverlayView(appState: AppState())
        .padding()
        .background(Color.blue)
}
