//
//  AppTheme.swift
//  Recod
//
//  Created for OpenCode.
//

import SwiftUI

enum AppTheme {
    // MARK: - Layout

    static let padding: CGFloat = 16
    static let pagePadding: CGFloat = 30
    static let cornerRadius: CGFloat = 16
    static let smallCornerRadius: CGFloat = 8
    static let spacing: CGFloat = 12

    // MARK: - Sidebar Layout

    static let sidebarWidthExpanded: CGFloat = 200
    static let sidebarWidthCollapsed: CGFloat = 68
    static let sidebarTopSpacing: CGFloat = 20
    static let sidebarButtonBottomSpacing: CGFloat = 24

    // MARK: - Styling

    static let glassMaterial: Material = .regular
    static let activeMaterial: Material = .thick
    static let inactiveOpacity: CGFloat = 0.6
    static let shadowColor: Color = .black.opacity(0.05)
    static let shadowRadius: CGFloat = 5
    static let shadowY: CGFloat = 2
    // MARK: - Header Layout

    static let headerIconSize: CGFloat = 32
    static let headerIconFrameWidth: CGFloat = 40

    // MARK: - Overlay

    static let overlayContainerSize: CGFloat = 72
    static let overlayCoreSize: CGFloat = 34
    static let overlayIconSize: CGFloat = 18
    static let overlayIconContainerSize: CGFloat = 28
    static let overlayRippleMiddleSize: CGFloat = 56
    static let overlayReadyDelayNanoseconds: UInt64 = 280_000_000

    static let overlayStateSpringResponse: CGFloat = 0.34
    static let overlayStateSpringDamping: CGFloat = 0.84
    static let overlayRecordingTransitionScale: CGFloat = 0.94

    static let overlayTimelineFPS: Double = 30

    static let overlaySuccessIconSize: CGFloat = 25
    static let overlayErrorIconSize: CGFloat = 24
    static let overlayStatusShadowRadius: CGFloat = 10
    static let overlayStatusShadowY: CGFloat = 4

    static let overlayTranscribingRotationSpeed: Double = 2.4
    static let overlayTranscribingCenterDotSize: CGFloat = 8
    static let overlayTranscribingOrbitDotSize: CGFloat = 7
    static let overlayTranscribingOrbitRadius: CGFloat = 15
    static let overlayTranscribingOrbitDots: Int = 3
    static let overlayPostProcessingOrbitDots: Int = 5

    static let overlayTranscribingTint: Color = .red
    static let overlayPostProcessingTint: Color = .blue
    static let overlayLoaderPrimaryOpacity: CGFloat = 0.95
    static let overlayLoaderSecondaryOpacity: CGFloat = 0.78
    static let overlayLoaderCenterShadowOpacity: CGFloat = 0.45
    static let overlayLoaderOrbitShadowOpacity: CGFloat = 0.35
    static let overlayLoaderCenterShadowRadius: CGFloat = 7
    static let overlayLoaderOrbitShadowRadius: CGFloat = 6

    static let overlayLevelGateThreshold: CGFloat = 0.075
    static let overlayLevelGateRange: CGFloat = 0.925
    static let overlayLevelCurvePower: CGFloat = 0.78

    static let overlayIdleIntensityThreshold: CGFloat = 0.06
    static let overlayIdleIntensityValue: CGFloat = 0.028

    static let overlayBurstDuration: TimeInterval = 0.92
    static let overlayBurstRisingThreshold: CGFloat = 0.045
    static let overlayBurstSustainedThreshold: CGFloat = 0.52
    static let overlayBurstSustainedInterval: TimeInterval = 0.95
    static let overlayBurstTriggerThreshold: CGFloat = 0.16
    static let overlayBurstCooldownMin: TimeInterval = 0.48
    static let overlayBurstCooldownBase: TimeInterval = 0.9
    static let overlayBurstCooldownLevelFactor: Double = 0.34
    static let overlayBurstIntensityMin: CGFloat = 0.2
    static let overlayBurstMaxCount: Int = 8
    static let overlayLoudBurstThreshold: CGFloat = 0.7
    static let overlayLoudBurstDelay: TimeInterval = 0.16
    static let overlayLoudBurstIntensityScale: CGFloat = 0.78

    static let overlayRippleExpansionBase: CGFloat = 1
    static let overlayRippleExpansionProgressScale: CGFloat = 0.95
    static let overlayRippleExpansionIntensityScale: CGFloat = 1.22
    static let overlayRippleOpacityBase: CGFloat = 0.14
    static let overlayRippleOpacityIntensityScale: CGFloat = 0.84
    static let overlayRippleOpacityFalloffPower: CGFloat = 1.28
    static let overlayRippleBlurBase: CGFloat = 0.04
    static let overlayRippleBlurProgressScale: CGFloat = 0.22
    static let overlayRippleBlurIntensityScale: CGFloat = 0.28
    static let overlayRippleLineWidthMin: CGFloat = 1.02
    static let overlayRippleLineWidthBase: CGFloat = 2.15
    static let overlayRippleLineWidthIntensityScale: CGFloat = 0.55
    static let overlayRippleLineWidthProgressScale: CGFloat = 0.92
    static let overlayRippleTintBase: CGFloat = 0.54
    static let overlayRippleTintIntensityScale: CGFloat = 0.32
    static let overlayRippleRedBaseOpacity: CGFloat = 0.45
    static let overlayRippleRedIntensityOpacity: CGFloat = 0.45

    static let overlayAuraScaleBase: CGFloat = 1.04
    static let overlayAuraScaleIntensity: CGFloat = 0.54
    static let overlayAuraOpacityBase: CGFloat = 0.06
    static let overlayAuraOpacityIntensity: CGFloat = 0.62
    static let overlayAuraBlurBase: CGFloat = 0.5
    static let overlayAuraBlurIntensity: CGFloat = 1.35
    static let overlayAuraStrokeWidth: CGFloat = 1.35
    static let overlayAuraRedBaseOpacity: CGFloat = 0.48
    static let overlayAuraRedIntensityOpacity: CGFloat = 0.4
    static let overlayAuraShadowBase: CGFloat = 0.32
    static let overlayAuraShadowIntensity: CGFloat = 0.42
    static let overlayAuraShadowRadius: CGFloat = 12
    static let overlayAuraAnimationDuration: CGFloat = 0.24
}
