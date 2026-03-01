import SwiftUI
import SwiftData

struct ReplacementRowView: View {
    let rule: ReplacementRule
    let containerWidth: CGFloat
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var isExpanded = false

    private var allPatterns: [String] {
        [rule.textToReplace] + rule.additionalIncorrectForms
    }

    var body: some View {
        // Calculate available width for content
        // Container - (GlassRow Padding * 2) - (HStack Spacing)
        let contentWidth = containerWidth - (AppTheme.padding * 2) - 16
        let leftWidth = contentWidth * 0.4
        let rightWidth = contentWidth * 0.6

        HStack(alignment: .top, spacing: 16) {

            // Patterns (40%)
            VStack(alignment: .leading, spacing: 4) {
                Text(allPatterns.joined(separator: ", "))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .contentShape(Rectangle()) // Make entire area tappable
            }
            .frame(width: leftWidth, alignment: .leading)
            .onTapGesture {
                withAnimation(.spring(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }

            // Replacement (60%)
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

                // Actions
                HStack(spacing: 12) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                            .foregroundStyle(isHovering ? .primary : .secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit Rule")

                    DeleteIconButton(action: onDelete)
                }
                .opacity(isHovering ? 1.0 : 0.6)
            }
            .frame(width: rightWidth, alignment: .leading)
        }
        .glassRowStyle(isHovering: isHovering)
        .onHover { isHovering = $0 }
    }
}
