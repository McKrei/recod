import SwiftUI

/// A toggle switch with a status indicator dot (green for on, red for off) and a slightly smaller scale.
///
/// Use this component for settings that require a visual indication of active/inactive state
/// beyond the standard toggle switch.
///
/// Example usage:
/// ```swift
/// StatusToggle(isOn: $isEnabled)
/// ```
struct StatusToggle: View {
    /// A binding to the boolean state of the toggle.
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .scaleEffect(0.85)
            .overlay(
                Circle()
                    .fill(isOn ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .offset(x: -20),
                alignment: .leading
            )
    }
}

#Preview {
    VStack {
        StatusToggle(isOn: .constant(true))
        StatusToggle(isOn: .constant(false))
    }
    .padding()
}
