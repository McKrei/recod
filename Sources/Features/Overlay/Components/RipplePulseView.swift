import SwiftUI

/// A single expanding and fading ring that reacts to speech bursts.
struct RipplePulseView: View {
    let progress: CGFloat
    let intensity: CGFloat

    var body: some View {
        let clamped = min(max(progress, 0), 1)
        let expansion = AppTheme.overlayRippleExpansionBase + (clamped * (AppTheme.overlayRippleExpansionProgressScale + (AppTheme.overlayRippleExpansionIntensityScale * intensity)))
        let alphaFalloff = pow(1 - clamped, AppTheme.overlayRippleOpacityFalloffPower)
        let opacity = Double((AppTheme.overlayRippleOpacityBase + AppTheme.overlayRippleOpacityIntensityScale * intensity) * alphaFalloff)
        let blur = AppTheme.overlayRippleBlurBase + (AppTheme.overlayRippleBlurProgressScale * clamped) + (AppTheme.overlayRippleBlurIntensityScale * intensity)
        let lineWidth = max(
            AppTheme.overlayRippleLineWidthMin,
            (AppTheme.overlayRippleLineWidthBase + AppTheme.overlayRippleLineWidthIntensityScale * intensity) - (clamped * AppTheme.overlayRippleLineWidthProgressScale)
        )
        let tint = AppTheme.overlayRippleTintBase + (AppTheme.overlayRippleTintIntensityScale * intensity)

        Circle()
            .stroke(
                AngularGradient(
                    colors: [
                        .white.opacity(0.98),
                        .pink.opacity(tint),
                        .red.opacity(AppTheme.overlayRippleRedBaseOpacity + (AppTheme.overlayRippleRedIntensityOpacity * intensity)),
                        .white.opacity(0.98)
                    ],
                    center: .center
                ),
                lineWidth: lineWidth
            )
            .frame(width: AppTheme.overlayCoreSize, height: AppTheme.overlayCoreSize)
            .scaleEffect(expansion)
            .opacity(opacity)
            .blur(radius: blur)
            .shadow(color: .white.opacity(opacity * 0.55), radius: 10, x: 0, y: 0)
            .shadow(color: .red.opacity(opacity * 0.45), radius: 14, x: 0, y: 0)
            .blendMode(.plusLighter)
    }
}

#Preview {
    ZStack {
        Color.black
        RipplePulseView(progress: 0.5, intensity: 1.0)
    }
}
