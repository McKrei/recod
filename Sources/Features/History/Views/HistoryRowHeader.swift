import SwiftUI

struct HistoryRowHeader: View {
    let createdAt: Date
    let durationText: String
    let canRunPostProcessing: Bool
    let postProcessingActions: [PostProcessingAction]
    let latestActionName: String?
    let onRunPostProcessing: (PostProcessingAction) -> Void

    @ViewBuilder
    private var postProcessingButtonLabel: some View {
        if let latestActionName {
            Text(String(latestActionName.prefix(3)))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    var body: some View {
        HStack {
            Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if canRunPostProcessing {
                Menu {
                    ForEach(postProcessingActions) { action in
                        Button(action.name) {
                            onRunPostProcessing(action)
                        }
                    }
                } label: {
                    postProcessingButtonLabel
                        .frame(width: 28, height: 18)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Run post-processing")
            }

            Text(durationText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
}
