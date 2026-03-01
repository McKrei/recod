//
//  OverlayView.swift
//  Recod
//
//  Created for OpenCode.
//

import SwiftUI

struct OverlayView: View {
    @ObservedObject var appState: AppState
    @State private var isUIReady = false
    @State private var readyTask: Task<Void, Never>?
    @State private var rippleBursts: [RippleBurst] = []
    @State private var lastBurstTime: TimeInterval = 0
    @State private var previousVisualLevel: CGFloat = 0

    var body: some View {
        ZStack {
            statusContent
        }
        .frame(width: AppTheme.overlayContainerSize, height: AppTheme.overlayContainerSize)
        .animation(.spring(response: AppTheme.overlayStateSpringResponse, dampingFraction: AppTheme.overlayStateSpringDamping), value: isUIReady)
        .animation(.spring(response: AppTheme.overlayStateSpringResponse, dampingFraction: AppTheme.overlayStateSpringDamping), value: appState.overlayStatus)
        .onAppear {
            scheduleRecordingReady()
        }
        .onDisappear {
            readyTask?.cancel()
            readyTask = nil
        }
        .onChange(of: appState.isRecording) { _, isRecording in
            if isRecording {
                scheduleRecordingReady()
            } else {
                isUIReady = false
                resetRippleState()
            }
        }
        .onChange(of: appState.overlayStatus) { _, newStatus in
            if newStatus != .recording {
                resetRippleState()
            }
        }
        .onChange(of: appState.overlayAudioLevel) { _, level in
            registerRippleBurst(with: level)
        }
    }

    // MARK: - Status Views

    private var audioLevel: CGFloat {
        CGFloat(min(max(appState.overlayAudioLevel, 0), 1))
    }

    @ViewBuilder
    private var statusContent: some View {
        switch appState.overlayStatus {
        case .recording:
            recordingContent
                .transition(.scale(scale: AppTheme.overlayRecordingTransitionScale).combined(with: .opacity))
        case .transcribing:
            transcribingContent
                .transition(.opacity)
        case .success:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: AppTheme.overlaySuccessIconSize, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [.mint.opacity(0.95), .green.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: .green.opacity(0.32), radius: AppTheme.overlayStatusShadowRadius, x: 0, y: AppTheme.overlayStatusShadowY)
                .symbolEffect(.bounce, options: .speed(1.2))
                .transition(.scale.combined(with: .opacity))
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: AppTheme.overlayErrorIconSize, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: [.orange.opacity(0.95), .red.opacity(0.88)], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: .red.opacity(0.35), radius: AppTheme.overlayStatusShadowRadius, x: 0, y: AppTheme.overlayStatusShadowY)
                .symbolEffect(.bounce, options: .speed(1.2))
                .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var recordingContent: some View {
        if isUIReady {
            TimelineView(.animation(minimumInterval: 1.0 / AppTheme.overlayTimelineFPS, paused: false)) { context in
                let level = visualLevel
                let idleLevel = minIdleIntensity(for: level)
                let leadIntensity = max(level, idleLevel)
                let now = context.date.timeIntervalSinceReferenceDate

                ZStack {
                    ambientVoiceAura(intensity: leadIntensity)

                    ForEach(rippleBursts) { burst in
                        if let progress = burstProgress(for: burst, at: now) {
                            reactiveRipplePulse(progress: progress, intensity: burst.intensity)
                        }
                    }

                    micCore
                }
            }
        } else {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
        }
    }

    private var visualLevel: CGFloat {
        visualLevel(for: audioLevel)
    }

    private func minIdleIntensity(for level: CGFloat) -> CGFloat {
        level < AppTheme.overlayIdleIntensityThreshold ? AppTheme.overlayIdleIntensityValue : 0
    }

    // MARK: - Recording Visuals

    private var micCore: some View {
        ZStack {
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
                .shadow(color: .red.opacity(0.35 + Double(audioLevel) * 0.35), radius: 10, x: 0, y: 3)

            Image(systemName: "mic.fill")
                .font(.system(size: AppTheme.overlayIconSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.98))
        }
    }

    private var transcribingContent: some View {
        TimelineView(.animation(minimumInterval: 1.0 / AppTheme.overlayTimelineFPS, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let rotation = time * AppTheme.overlayTranscribingRotationSpeed

            ZStack {
                Circle()
                    .fill(.red.opacity(0.95))
                    .frame(width: AppTheme.overlayTranscribingCenterDotSize, height: AppTheme.overlayTranscribingCenterDotSize)
                    .shadow(color: .red.opacity(0.45), radius: 7, x: 0, y: 0)

                ForEach(0 ..< 3, id: \.self) { index in
                    let angle = rotation + (Double(index) * (2 * .pi / 3))
                    Circle()
                        .fill(.red.opacity(index == 0 ? 0.95 : 0.78))
                        .frame(width: AppTheme.overlayTranscribingOrbitDotSize, height: AppTheme.overlayTranscribingOrbitDotSize)
                        .offset(x: cos(angle) * AppTheme.overlayTranscribingOrbitRadius, y: sin(angle) * AppTheme.overlayTranscribingOrbitRadius)
                        .shadow(color: .red.opacity(0.35), radius: 6, x: 0, y: 0)
                }
            }
        }
    }

    // MARK: - Burst Logic

    private func registerRippleBurst(with levelValue: Float) {
        guard appState.overlayStatus == .recording, isUIReady else { return }

        let now = Date.timeIntervalSinceReferenceDate
        let current = visualLevel(for: CGFloat(min(max(levelValue, 0), 1)))
        rippleBursts.removeAll { now - $0.startTime > AppTheme.overlayBurstDuration }

        let rising = current - previousVisualLevel
        let enoughRise = rising > AppTheme.overlayBurstRisingThreshold
        let sustainedSpeech = current > AppTheme.overlayBurstSustainedThreshold && (now - lastBurstTime) > AppTheme.overlayBurstSustainedInterval
        let thresholdPassed = current > AppTheme.overlayBurstTriggerThreshold && enoughRise
        let cooldown = max(AppTheme.overlayBurstCooldownMin, AppTheme.overlayBurstCooldownBase - (AppTheme.overlayBurstCooldownLevelFactor * Double(current)))

        if (thresholdPassed || sustainedSpeech), (now - lastBurstTime) >= cooldown {
            let intensity = min(max(current, AppTheme.overlayBurstIntensityMin), 1)
            rippleBursts.append(RippleBurst(startTime: now, intensity: intensity))

            if intensity > AppTheme.overlayLoudBurstThreshold {
                rippleBursts.append(
                    RippleBurst(
                        startTime: now + AppTheme.overlayLoudBurstDelay,
                        intensity: intensity * AppTheme.overlayLoudBurstIntensityScale
                    )
                )
            }

            if rippleBursts.count > AppTheme.overlayBurstMaxCount {
                rippleBursts.removeFirst(rippleBursts.count - AppTheme.overlayBurstMaxCount)
            }
            lastBurstTime = now
        }

        previousVisualLevel = current
    }

    private func visualLevel(for raw: CGFloat) -> CGFloat {
        let gated = max(raw - AppTheme.overlayLevelGateThreshold, 0) / AppTheme.overlayLevelGateRange
        let boosted = pow(gated, AppTheme.overlayLevelCurvePower)
        return min(max(boosted, 0), 1)
    }

    private func burstProgress(for burst: RippleBurst, at time: TimeInterval) -> CGFloat? {
        let elapsed = time - burst.startTime
        guard elapsed >= 0, elapsed <= AppTheme.overlayBurstDuration else { return nil }
        return CGFloat(elapsed / AppTheme.overlayBurstDuration)
    }

    // MARK: - Drawing

    private func reactiveRipplePulse(progress: CGFloat, intensity: CGFloat) -> some View {
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

        return Circle()
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

    private func ambientVoiceAura(intensity: CGFloat) -> some View {
        let clamped = min(max(intensity, 0), 1)
        let scale = AppTheme.overlayAuraScaleBase + clamped * AppTheme.overlayAuraScaleIntensity
        let opacity = AppTheme.overlayAuraOpacityBase + Double(clamped) * AppTheme.overlayAuraOpacityIntensity
        let blur = AppTheme.overlayAuraBlurBase + clamped * AppTheme.overlayAuraBlurIntensity

        return Circle()
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
            .shadow(color: .red.opacity(AppTheme.overlayAuraShadowBase + AppTheme.overlayAuraShadowIntensity * clamped), radius: AppTheme.overlayAuraShadowRadius, x: 0, y: 0)
            .animation(.easeOut(duration: AppTheme.overlayAuraAnimationDuration), value: clamped)
    }

    private func resetRippleState() {
        rippleBursts.removeAll()
        lastBurstTime = 0
        previousVisualLevel = 0
    }

    // MARK: - Lifecycle

    private func scheduleRecordingReady() {
        readyTask?.cancel()
        isUIReady = false

        readyTask = Task {
            try? await Task.sleep(nanoseconds: AppTheme.overlayReadyDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.24)) {
                    isUIReady = true
                }
            }
        }
    }

}

private struct RippleBurst: Identifiable {
    let id = UUID()
    let startTime: TimeInterval
    let intensity: CGFloat
}

#Preview {
    OverlayView(appState: AppState())
        .padding()
        .background(Color.blue)
}
