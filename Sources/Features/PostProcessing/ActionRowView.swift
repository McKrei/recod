import SwiftUI

struct ActionRowView: View {
    let action: PostProcessingAction
    let onAutoEnabledChange: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var isEditHovering = false

    private var providerTitle: String {
        LLMProviderStore.provider(for: action.providerID)?.displayName ?? "Unknown Provider"
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(action.name)
                        .font(.headline)

                    Text(providerTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(action.modelID)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Text(action.prompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 10) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .foregroundStyle(isEditHovering || isHovering ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit action")
                    .onHover { isEditHovering = $0 }

                    DeleteIconButton(action: onDelete)
                }

                Toggle("", isOn: Binding(
                    get: { action.isAutoEnabled },
                    set: { onAutoEnabledChange($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.85)
            }
            .frame(width: 90, alignment: .trailing)
            .contentShape(Rectangle())
            .onTapGesture {
                // Prevent row tap from opening editor when interacting with controls.
            }
        }
        .glassRowStyle(isHovering: isHovering)
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
    }
}
