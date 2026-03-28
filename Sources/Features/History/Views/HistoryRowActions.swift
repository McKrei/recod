import SwiftUI

struct HistoryRowActions: View {
    let transcriptionStatus: Recording.TranscriptionStatus
    let textToCopy: String?
    let showCopyFeedback: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if (transcriptionStatus == .completed || transcriptionStatus == .streamingTranscription),
               let textToCopy,
               !textToCopy.isEmpty {
                Button(action: onCopy) {
                    Image(systemName: showCopyFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundStyle(showCopyFeedback ? .green : .secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Copy")
            }

            DeleteIconButton(action: onDelete)
                .scaleEffect(0.9)
        }
        .padding(.top, 2)
    }
}
