import SwiftUI

struct SidebarView: View {
    @Binding var selection: SettingsSelection?
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top spacing for traffic lights (approx 28pt standard)
            Color.clear.frame(height: AppTheme.sidebarTopSpacing)

            // Toggle Button (Moved to top)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "sidebar.left" : "sidebar.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
            .padding(.leading, isExpanded ? 16 : 0)
            .padding(.bottom, AppTheme.sidebarButtonBottomSpacing)

            // Navigation Items
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(SettingsSelection.allCases) { item in
                        SidebarItem(
                            item: item,
                            isSelected: selection == item,
                            isExpanded: isExpanded
                        ) {
                            selection = item
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer()
        }
        .frame(width: isExpanded ? AppTheme.sidebarWidthExpanded : AppTheme.sidebarWidthCollapsed)
        .background(.ultraThinMaterial)
    }
}

struct SidebarItem: View {
    let item: SettingsSelection
    let isSelected: Bool
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                if isExpanded {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.title)
    }
}
