import SwiftUI
import SwiftData

struct ReplacementRowView: View {
    let rule: ReplacementRule
    let containerWidth: CGFloat
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var allPatterns: [String] {
        [rule.textToReplace] + rule.additionalIncorrectForms
    }

    var body: some View {
        let contentWidth = containerWidth - (AppTheme.padding * 2) - AppTheme.spacing
        let leftWidth = contentWidth * 0.4
        let rightWidth = contentWidth * 0.6

        InteractiveGlassRow(onTap: onEdit) { isHovering in
            HStack(alignment: .top, spacing: AppTheme.spacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(allPatterns.joined(separator: ", "))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .contentShape(Rectangle())
                }
                .frame(width: leftWidth, alignment: .leading)

                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.replacementText)
                            .font(.body)
                            .bold()
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            if rule.useFuzzyMatching {
                                Label("Fuzzy", systemImage: "sparkles")
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }

                            let weightText = rule.weight > 1.5 ? "High" : (rule.weight < 1.5 ? "Low" : "Normal")
                            Label(weightText, systemImage: "arrow.up.circle")
                                .font(.system(size: 9))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        EditIconButton(action: onEdit)
                            .help("Edit Rule")

                        DeleteIconButton(action: onDelete)
                    }
                    .opacity(isHovering ? 1.0 : 0.6)
                }
                .frame(width: rightWidth, alignment: .leading)
            }
        }
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit Rule", systemImage: "pencil")
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete Rule", systemImage: "trash")
            }
        }
    }
}
