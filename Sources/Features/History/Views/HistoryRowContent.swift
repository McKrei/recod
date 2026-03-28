import SwiftUI

struct HistoryRowContent: View {
    let recording: Recording
    let transcriptionStatus: Recording.TranscriptionStatus
    let latestPostProcessedResult: PostProcessedResult?
    let latestPostProcessedText: String?
    let textForCopy: String?
    let onCancelRetranscribe: () -> Void

    @Binding var isExpanded: Bool
    @Binding var isSegmentsExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch transcriptionStatus {
            case .transcribing:
                statusContent(title: "Transcribing...", accent: .secondary, showsProgress: true)
            case .postProcessing:
                statusContent(title: "Post-processing...", accent: .secondary, showsProgress: true)
            case .streamingTranscription:
                streamingContent
            case .queued:
                queuedContent
            case .completed:
                completedContent
            case .failed:
                labelRow(systemImage: "exclamationmark.triangle.fill", text: "Transcription failed", color: .orange)
            case .cancelled:
                labelRow(systemImage: "slash.circle", text: "Retranscription cancelled", color: .secondary)
            case .pending:
                Text("Pending...")
                    .italic()
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func statusContent(title: String, accent: Color, showsProgress: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(title)
                    .foregroundStyle(accent)
            }

            if let text = textForCopy.nilIfBlank {
                expandableText(text, foregroundStyle: .primary)
            }
        }
    }

    @ViewBuilder
    private var streamingContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)

                Text("Recording & Transcribing...")
                    .foregroundStyle(.red)
                    .font(.caption.bold())
            }

            if let liveText = recording.liveTranscription, !liveText.isEmpty {
                expandableText(liveText, foregroundStyle: .primary)

                if isExpanded, let segments = recording.segments, !segments.isEmpty {
                    timelineToggle(title: isSegmentsExpanded ? "Hide Transcription" : "Show Transcription")

                    if isSegmentsExpanded {
                        TranscriptionDetailView(segments: segments)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            } else {
                Text("Listening...")
                    .italic()
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var queuedContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.2.circlepath")
                .foregroundStyle(.secondary)

            Text("Queued for retranscription")
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onCancelRetranscribe) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel")
        }
    }

    @ViewBuilder
    private var completedContent: some View {
        if let transcription = recording.transcription, !transcription.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if let latestPostProcessedText {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                                .foregroundStyle(.secondary)

                            Text("After Post-Processing")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            if let actionName = latestPostProcessedResult?.actionName {
                                Text(actionName)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        expandableText(latestPostProcessedText, foregroundStyle: .primary)

                        if isExpanded {
                            Divider()

                            Text("Before Post-Processing")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            Text(transcription)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if let segments = recording.segments, !segments.isEmpty {
                                timelineToggle(title: isSegmentsExpanded ? "Hide Timeline" : "Show Timeline")

                                if isSegmentsExpanded {
                                    TranscriptionDetailView(segments: segments)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                        }
                    }
                } else {
                    expandableText(transcription, foregroundStyle: .primary)

                    if isExpanded, let segments = recording.segments, !segments.isEmpty {
                        timelineToggle(title: isSegmentsExpanded ? "Hide Transcription" : "Show Transcription")

                        if isSegmentsExpanded {
                            TranscriptionDetailView(segments: segments)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
            }
        } else {
            Text("Empty transcription")
                .italic()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func expandableText(_ text: String, foregroundStyle: Color) -> some View {
        Text(text)
            .foregroundStyle(foregroundStyle)
            .lineLimit(isExpanded ? nil : 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(duration: 0.3)) {
                    isExpanded.toggle()
                    if !isExpanded {
                        isSegmentsExpanded = false
                    }
                }
            }
    }

    @ViewBuilder
    private func timelineToggle(title: String) -> some View {
        Button {
            withAnimation(.spring(duration: 0.4)) {
                isSegmentsExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(isSegmentsExpanded ? 180 : 0))
            }
            .font(.caption.bold())
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func labelRow(systemImage: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}
