import SwiftUI

struct SettingsPageContainer<Action: View, Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: Action
    let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder action: () -> Action,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.action = action()
        self.content = content()
    }

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) where Action == EmptyView {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            action: { EmptyView() },
            content: content
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.padding) {
                SettingsHeaderView(
                    title: title,
                    subtitle: subtitle,
                    systemImage: systemImage
                ) {
                    action
                }

                content
            }
            .padding(AppTheme.pagePadding)
        }
    }
}
