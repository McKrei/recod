import SwiftUI

/// A rotating orbital loader used during the transcription phase.
/// Consists of a center dot and three orbiting dots.
struct TranscribingIndicator: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / AppTheme.overlayTimelineFPS, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let rotation = time * AppTheme.overlayTranscribingRotationSpeed

            ZStack {
                // Center core dot
                Circle()
                    .fill(.red.opacity(0.95))
                    .frame(width: AppTheme.overlayTranscribingCenterDotSize, height: AppTheme.overlayTranscribingCenterDotSize)
                    .shadow(color: .red.opacity(0.45), radius: 7, x: 0, y: 0)

                // Orbiting dots
                ForEach(0 ..< 3, id: \.self) { index in
                    let angle = rotation + (Double(index) * (2 * .pi / 3))
                    Circle()
                        .fill(.red.opacity(index == 0 ? 0.95 : 0.78))
                        .frame(width: AppTheme.overlayTranscribingOrbitDotSize, height: AppTheme.overlayTranscribingOrbitDotSize)
                        .offset(
                            x: cos(angle) * AppTheme.overlayTranscribingOrbitRadius,
                            y: sin(angle) * AppTheme.overlayTranscribingOrbitRadius
                        )
                        .shadow(color: .red.opacity(0.35), radius: 6, x: 0, y: 0)
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black
        TranscribingIndicator()
    }
}
