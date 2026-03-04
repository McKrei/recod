//
//  OverlayView.swift
//  Recod
//
//  Created for OpenCode.
//

import SwiftUI

/// Main view for the floating overlay that shows recording/transcription status.
/// Coordinates animations and sub-components based on `OverlayState`.
struct OverlayView: View {
    @ObservedObject var overlayState: OverlayState
    @State private var isUIReady = false
    @State private var readyTask: Task<Void, Never>?
    @State private var rippleBursts: [RippleBurst] = []
    @State private var lastBurstTime: TimeInterval = 0
    @State private var previousVisualLevel: CGFloat = 0

    init(overlayState: OverlayState = OverlayState.shared) {
        self.overlayState = overlayState
    }

    var body: some View {
        ZStack {
            statusContent
        }
        .frame(width: AppTheme.overlayContainerSize, height: AppTheme.overlayContainerSize)
        .animation(.spring(response: AppTheme.overlayStateSpringResponse, dampingFraction: AppTheme.overlayStateSpringDamping), value: isUIReady)
        .animation(.spring(response: AppTheme.overlayStateSpringResponse, dampingFraction: AppTheme.overlayStateSpringDamping), value: overlayState.status)
        .onAppear {
            if overlayState.status == .recording { scheduleRecordingReady() }
        }
        .onDisappear {
            readyTask?.cancel()
            readyTask = nil
        }
        .onChange(of: overlayState.status) { _, newStatus in
            if newStatus == .recording {
                scheduleRecordingReady()
            } else {
                isUIReady = false
                resetRippleState()
            }
        }
        .onChange(of: overlayState.audioLevel) { _, level in
            registerRippleBurst(with: level)
        }
    }

    // MARK: - Status Views

    @ViewBuilder
    private var statusContent: some View {
        switch overlayState.status {
        case .recording:
            recordingContent
                .transition(.scale(scale: AppTheme.overlayRecordingTransitionScale).combined(with: .opacity))
        case .transcribing:
            TranscribingIndicator(style: .transcribing)
                .transition(.opacity)
        case .postProcessing:
            TranscribingIndicator(style: .postProcessing)
                .transition(.opacity)
        case .success:
            successIcon
                .transition(.scale.combined(with: .opacity))
        case .error:
            errorContent
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
                    VoiceAuraView(intensity: leadIntensity)

                    ForEach(rippleBursts) { burst in
                        if let elapsed = burstElapsed(for: burst, at: now) {
                            RipplePulseView(progress: elapsed, intensity: burst.intensity)
                        }
                    }

                    MicCoreView(audioLevel: Float(overlayState.audioLevel))
                }
            }
        } else {
            ProgressView().controlSize(.small).tint(.white)
        }
    }

    private var successIcon: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: AppTheme.overlaySuccessIconSize, weight: .semibold))
            .foregroundStyle(
                LinearGradient(colors: [.mint.opacity(0.95), .green.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            )
            .shadow(color: .green.opacity(0.32), radius: AppTheme.overlayStatusShadowRadius, x: 0, y: AppTheme.overlayStatusShadowY)
            .symbolEffect(.bounce, options: .speed(1.2))
    }

    @ViewBuilder
    private var errorContent: some View {
        if let message = overlayState.errorMessage {
            VStack(spacing: 6) {
                errorIcon
                Text(message)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            errorIcon
        }
    }

    private var errorIcon: some View {
        Image(systemName: overlayState.errorMessage != nil ? "bluetooth.slash" : "exclamationmark.triangle.fill")
            .font(.system(size: AppTheme.overlayErrorIconSize, weight: .bold))
            .foregroundStyle(
                LinearGradient(colors: [.orange.opacity(0.95), .red.opacity(0.88)], startPoint: .top, endPoint: .bottom)
            )
            .shadow(color: .red.opacity(0.35), radius: AppTheme.overlayStatusShadowRadius, x: 0, y: AppTheme.overlayStatusShadowY)
            .symbolEffect(.bounce, options: .speed(1.2))
    }

    // MARK: - Animation Logic

    private var visualLevel: CGFloat {
        let raw = CGFloat(min(max(overlayState.audioLevel, 0), 1))
        let gated = max(raw - AppTheme.overlayLevelGateThreshold, 0) / AppTheme.overlayLevelGateRange
        let boosted = pow(gated, AppTheme.overlayLevelCurvePower)
        return min(max(boosted, 0), 1)
    }

    private func minIdleIntensity(for level: CGFloat) -> CGFloat {
        level < AppTheme.overlayIdleIntensityThreshold ? AppTheme.overlayIdleIntensityValue : 0
    }

    private func registerRippleBurst(with levelValue: Float) {
        guard overlayState.status == .recording, isUIReady else { return }

        let now = Date.timeIntervalSinceReferenceDate
        let current = visualLevel
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
                    RippleBurst(startTime: now + AppTheme.overlayLoudBurstDelay, intensity: intensity * AppTheme.overlayLoudBurstIntensityScale)
                )
            }
            if rippleBursts.count > AppTheme.overlayBurstMaxCount { rippleBursts.removeFirst() }
            lastBurstTime = now
        }
        previousVisualLevel = current
    }

    private func burstElapsed(for burst: RippleBurst, at time: TimeInterval) -> CGFloat? {
        let elapsed = time - burst.startTime
        guard elapsed >= 0, elapsed <= AppTheme.overlayBurstDuration else { return nil }
        return CGFloat(elapsed / AppTheme.overlayBurstDuration)
    }

    private func resetRippleState() {
        rippleBursts.removeAll(); lastBurstTime = 0; previousVisualLevel = 0
    }

    private func scheduleRecordingReady() {
        readyTask?.cancel(); isUIReady = false
        readyTask = Task {
            try? await Task.sleep(nanoseconds: AppTheme.overlayReadyDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation(.easeOut(duration: 0.24)) { isUIReady = true } }
        }
    }
}

#Preview {
    ZStack {
        Color.blue
        OverlayView()
    }
}
