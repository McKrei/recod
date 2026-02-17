import SwiftUI

struct TranscriptionDetailView: View {
    let segments: [TranscriptionSegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .opacity(0.3)

            ForEach(segments) { segment in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(formatTime(segment.start))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 45, alignment: .leading)

                    Text(segment.text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let tenths = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

#Preview {
    TranscriptionDetailView(segments: [
        TranscriptionSegment(start: 1.2, end: 3.5, text: "Hello, this is a test."),
        TranscriptionSegment(start: 3.8, end: 5.2, text: "Second segment of the transcription.")
    ])
    .padding()
    .frame(width: 300)
}
