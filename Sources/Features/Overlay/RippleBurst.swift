import Foundation

/// Data model representing a single speech burst event for UI animations.
struct RippleBurst: Identifiable, Sendable {
    let id = UUID()
    let startTime: TimeInterval
    let intensity: CGFloat
}
