import SwiftUI

/// Defines the visual state of the overlay window.
public enum OverlayStatus: Sendable {
    case recording
    case transcribing
    case success
    case error
}

/// Manages the state of the floating overlay window.
/// Decoupled from AppState to prevent the God Object anti-pattern.
@MainActor
public final class OverlayState: ObservableObject {
    public static let shared = OverlayState()

    @Published public var isVisible = false
    @Published public var status: OverlayStatus = .recording
    @Published public var audioLevel: Float = 0
    
    /// Optional custom error message shown in the overlay when `status == .error`.
    /// If nil, the overlay shows its default error icon.
    @Published public var errorMessage: String? = nil

    private init() {}

    /// Temporarily shows an error state with a custom message, then hides the overlay.
    public func showError(_ message: String? = nil, durationNanoseconds: UInt64 = 3_000_000_000) async {
        self.status = .error
        self.errorMessage = message
        self.isVisible = true
        
        try? await Task.sleep(nanoseconds: durationNanoseconds)
        
        self.errorMessage = nil
        self.isVisible = false
    }

    /// Temporarily shows a success state, then hides the overlay.
    public func showSuccess(durationNanoseconds: UInt64 = 1_500_000_000) async {
        self.status = .success
        self.isVisible = true
        
        try? await Task.sleep(nanoseconds: durationNanoseconds)
        
        self.isVisible = false
    }
}
