import SwiftUI

struct InteractiveGlassRow<Content: View>: View {
    let isSelected: Bool
    let onTap: (() -> Void)?
    let content: (Bool) -> Content

    @State private var isHovering = false

    init(
        isSelected: Bool = false,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Bool) -> Content
    ) {
        self.isSelected = isSelected
        self.onTap = onTap
        self.content = content
    }

    var body: some View {
        content(isHovering)
            .glassRowStyle(isSelected: isSelected, isHovering: isHovering)
            .onHover { isHovering = $0 }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap?()
            }
    }
}
