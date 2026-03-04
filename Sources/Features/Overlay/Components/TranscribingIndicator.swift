import SwiftUI

/// A rotating orbital loader used during the transcription phase.
/// Supports both transcription and post-processing styles.
struct TranscribingIndicator: View {
    enum Style {
        case transcribing
        case postProcessing

        var tint: Color {
            switch self {
            case .transcribing:
                return AppTheme.overlayTranscribingTint
            case .postProcessing:
                return AppTheme.overlayPostProcessingTint
            }
        }

        var orbitDots: Int {
            switch self {
            case .transcribing:
                return AppTheme.overlayTranscribingOrbitDots
            case .postProcessing:
                return AppTheme.overlayPostProcessingOrbitDots
            }
        }
    }

    let style: Style

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / AppTheme.overlayTimelineFPS, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let rotation = time * AppTheme.overlayTranscribingRotationSpeed
            let orbitCount = max(style.orbitDots, 1)
            let angleStep = 2 * Double.pi / Double(orbitCount)

            ZStack {
                // Center core dot
                Circle()
                    .fill(style.tint.opacity(AppTheme.overlayLoaderPrimaryOpacity))
                    .frame(width: AppTheme.overlayTranscribingCenterDotSize, height: AppTheme.overlayTranscribingCenterDotSize)
                    .shadow(color: style.tint.opacity(AppTheme.overlayLoaderCenterShadowOpacity), radius: AppTheme.overlayLoaderCenterShadowRadius, x: 0, y: 0)

                // Orbiting dots
                ForEach(0 ..< orbitCount, id: \.self) { index in
                    let angle = rotation + (Double(index) * angleStep)
                    Circle()
                        .fill(style.tint.opacity(index == 0 ? AppTheme.overlayLoaderPrimaryOpacity : AppTheme.overlayLoaderSecondaryOpacity))
                        .frame(width: AppTheme.overlayTranscribingOrbitDotSize, height: AppTheme.overlayTranscribingOrbitDotSize)
                        .offset(
                            x: cos(angle) * AppTheme.overlayTranscribingOrbitRadius,
                            y: sin(angle) * AppTheme.overlayTranscribingOrbitRadius
                        )
                        .shadow(color: style.tint.opacity(AppTheme.overlayLoaderOrbitShadowOpacity), radius: AppTheme.overlayLoaderOrbitShadowRadius, x: 0, y: 0)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: orbitCount)
            .animation(.easeInOut(duration: 0.25), value: style.tint)
        }
    }
}

#Preview {
    ZStack {
        Color.black
        TranscribingIndicator(style: .transcribing)
    }
}
