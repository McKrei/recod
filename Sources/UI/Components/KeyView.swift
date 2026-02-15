import SwiftUI

struct KeyView: View {
    var symbol: String?
    var text: String?

    var body: some View {
        Text(symbol ?? text ?? "")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(minWidth: 24, minHeight: 24)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Material.thick)
                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            )
    }
}
