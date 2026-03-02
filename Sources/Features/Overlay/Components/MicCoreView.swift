import SwiftUI

/// The central microphone button icon with a red glass gradient and shadow.
/// Reacts visually to the current audio level.
struct MicCoreView: View {
    let audioLevel: Float

    var body: some View {
        ZStack {
            // Background glass circle with gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.red.opacity(0.92), .red.opacity(0.64)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: AppTheme.overlayIconContainerSize, height: AppTheme.overlayIconContainerSize)
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.35), lineWidth: 0.8)
                )
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.35), .clear],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: AppTheme.overlayIconContainerSize
                            )
                        )
                )
                // Shadow responds to loudness
                .shadow(color: .red.opacity(0.35 + Double(audioLevel) * 0.35), radius: 10, x: 0, y: 3)

            // Mic icon
            Image(systemName: "mic.fill")
                .font(.system(size: AppTheme.overlayIconSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.98))
        }
    }
}

#Preview {
    ZStack {
        Color.gray
        MicCoreView(audioLevel: 0.5)
    }
}
