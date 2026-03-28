import SwiftUI

struct SettingsSectionCard<Content: View>: View {
    let title: String?
    let subtitle: String?
    let systemImage: String?
    let content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    private var showsHeader: Bool {
        title != nil || subtitle != nil || systemImage != nil
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: AppTheme.spacing) {
                if showsHeader {
                    HStack(alignment: .top, spacing: AppTheme.spacing) {
                        if let systemImage {
                            Image(systemName: systemImage)
                                .foregroundStyle(.secondary)
                                .frame(width: AppTheme.headerIconFrameWidth, alignment: .leading)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            if let title {
                                Text(title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            }

                            if let subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    Divider()
                }

                content
            }
        }
        .groupBoxStyle(GlassGroupBoxStyle())
    }
}
