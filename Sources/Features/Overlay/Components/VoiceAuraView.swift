import SwiftUI

/// An ambient glow that pulse behind the microphone, reflecting the 
/// current audio intensity (0.0 to 1.0).
struct VoiceAuraView: View {
    let intensity: CGFloat

    var body: some View {
        let clamped = min(max(intensity, 0), 1)
        let scale = AppTheme.overlayAuraScaleBase + clamped * AppTheme.overlayAuraScaleIntensity
        let opacity = AppTheme.overlayAuraOpacityBase + Double(clamped) * AppTheme.overlayAuraOpacityIntensity
        let blur = AppTheme.overlayAuraBlurBase + clamped * AppTheme.overlayAuraBlurIntensity

        Circle()
            .stroke(
                RadialGradient(
                    colors: [
                        .white.opacity(0.7),
                        .red.opacity(AppTheme.overlayAuraRedBaseOpacity + AppTheme.overlayAuraRedIntensityOpacity * clamped),
                        .clear
                    ],
                    center: .center,
                    startRadius: 1,
                    endRadius: AppTheme.overlayRippleMiddleSize
                ),
                lineWidth: AppTheme.overlayAuraStrokeWidth
            )
            .frame(width: AppTheme.overlayCoreSize, height: AppTheme.overlayCoreSize)
            .scaleEffect(scale)
            .opacity(opacity)
            .blur(radius: blur)
            .shadow(
                color: .red.opacity(AppTheme.overlayAuraShadowBase + AppTheme.overlayAuraShadowIntensity * clamped),
                radius: AppTheme.overlayAuraShadowRadius, 
                x: 0, y: 0
            )
            .animation(.easeOut(duration: AppTheme.overlayAuraAnimationDuration), value: clamped)
    }
}

#Preview {
    ZStack {
        Color.black
        VoiceAuraView(intensity: 0.8)
    }
}
