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
    @State private var isUIReady = false

    var body: some View {
        ZStack {
            // Background Glass Circle
            Circle()
                .fill(AppTheme.glassMaterial)
                .frame(width: 56, height: 56)
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)

            if isUIReady {
                Group {
                    // Pulsating Pulse
                    Circle()
                        .stroke(.red.opacity(0.6), lineWidth: 2)
                        .frame(width: 20, height: 20)
                        .scaleEffect(isAnimating ? 2.2 : 1.0)
                        .opacity(isAnimating ? 0 : 1)
                        .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: isAnimating)

                    // Recording Icon
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.red)
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .opacity
                ))
            } else {
                // Loading / Preparing State
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.4), value: isUIReady)
        .onAppear {
            startFakeDelay()
        }
        .onChange(of: appState.isRecording) { _, isRecording in
            if isRecording {
                startFakeDelay()
            } else {
                isUIReady = false
                isAnimating = false
            }
        }
    }
    
    private func startFakeDelay() {
        isUIReady = false
        isAnimating = false
        
        Task {
            // Artificial delay to allow audio engine to stabilize
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            await MainActor.run {
                withAnimation {
                    isUIReady = true
                    isAnimating = true
                }
            }
        }
    }
}

#Preview {
    OverlayView(appState: AppState())
        .padding()
        .background(Color.blue)
}
