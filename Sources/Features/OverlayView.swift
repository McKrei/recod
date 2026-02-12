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
        HStack(spacing: 12) {
            Image(systemName: "mic.circle.fill")
                .font(.largeTitle)
                .symbolEffect(.pulse.byLayer, options: .repeating, isActive: isAnimating)
                .foregroundStyle(.red, .primary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Listening")
                    .font(.headline)
                Text("MacAudio2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 3) {
                ForEach(0..<8) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.primary.opacity(0.6))
                        .frame(width: 4, height: 16)
                        .modifier(WaveformEffect(index: index, audioLevel: appState.audioLevel, isAnimating: isAnimating))
                }
            }
            .frame(height: 30)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(width: 300)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .onAppear {
            isAnimating = true
        }
    }
}

struct WaveformEffect: ViewModifier {
    let index: Int
    let audioLevel: Float
    let isAnimating: Bool
    
    func body(content: Content) -> some View {
        // Simple visualizer: height depends on audioLevel + some random jitter
        // We use .animation to smooth out updates
        let baseHeight: CGFloat = 8.0
        let maxHeight: CGFloat = 24.0
        
        // Pseudo-random variation based on index so bars don't look identical
        let variation = CGFloat((index % 3) + 1) * 2.0
        
        // Calculate target height
        let targetHeight = baseHeight + (CGFloat(audioLevel) * (maxHeight - baseHeight)) + (isAnimating && audioLevel > 0.01 ? variation : 0)
        
        return content
            .frame(height: targetHeight)
            .animation(.easeInOut(duration: 0.1), value: targetHeight)
    }
}

#Preview {
    OverlayView(appState: AppState())
        .padding()
        .background(Color.blue)
}
