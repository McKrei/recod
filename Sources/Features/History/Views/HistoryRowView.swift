import SwiftUI
import SwiftData

struct HistoryRowView: View {
    let recording: Recording
    let audioPlayer: AudioPlayer
    let onDelete: () -> Void
    let onDeleteAudioOnly: () -> Void

    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var isSegmentsExpanded = false
    @State private var showCopyFeedback = false

    private var isCurrentPlaying: Bool {
        audioPlayer.currentRecordingID == recording.id && audioPlayer.isPlaying
    }

    private var latestPostProcessedResult: PostProcessedResult? {
        recording.postProcessedResults?.max(by: { $0.createdAt < $1.createdAt })
    }

    private var latestPostProcessedText: String? {
        guard let text = latestPostProcessedResult?.outputText.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private var textForCopy: String? {
        if let postProcessed = latestPostProcessedText {
            return postProcessed
        }
        return recording.transcription ?? recording.liveTranscription
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing) {
            if recording.transcriptionStatus != .streamingTranscription && !recording.isFileDeleted {
                playPauseButton
                    .padding(.top, 2)
            } else {
                Color.clear
                    .frame(width: 26, height: 26)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Header: Date and Duration
                HStack {
                    Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(formatDuration(recording.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                // Transcription Content
                VStack(alignment: .leading, spacing: 4) {
                    switch recording.transcriptionStatus ?? .completed {
                    case .transcribing:
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Transcribing...")
                                    .foregroundStyle(.secondary)
                            }

                            if let text = textForCopy?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                                Text(text)
                                    .foregroundStyle(.primary)
                                    .lineLimit(isExpanded ? nil : 2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.spring(duration: 0.3)) {
                                            isExpanded.toggle()
                                            if !isExpanded { isSegmentsExpanded = false }
                                        }
                                    }
                            }
                        }
                    case .postProcessing:
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Post-processing...")
                                    .foregroundStyle(.secondary)
                            }

                            if let text = textForCopy?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                                Text(text)
                                    .foregroundStyle(.primary)
                                    .lineLimit(isExpanded ? nil : 2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.spring(duration: 0.3)) {
                                            isExpanded.toggle()
                                            if !isExpanded { isSegmentsExpanded = false }
                                        }
                                    }
                            }
                        }
                    case .streamingTranscription:
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
                                Text(liveText)
                                    .foregroundStyle(.primary)
                                    .lineLimit(isExpanded ? nil : 2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.spring(duration: 0.3)) {
                                            isExpanded.toggle()
                                            if !isExpanded { isSegmentsExpanded = false }
                                        }
                                    }

                                // "Show Transcription" Button (only if segments exist AND expanded)
                                if isExpanded, let segments = recording.segments, !segments.isEmpty {
                                    Button {
                                        withAnimation(.spring(duration: 0.4)) {
                                            isSegmentsExpanded.toggle()
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(isSegmentsExpanded ? "Hide Transcription" : "Show Transcription")
                                            Image(systemName: "chevron.down")
                                                .rotationEffect(.degrees(isSegmentsExpanded ? 180 : 0))
                                        }
                                        .font(.caption.bold())
                                        .foregroundStyle(Color.accentColor)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 2)

                                    // Detailed Segments List
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
                    case .completed:
                        if let transcription = recording.transcription, !transcription.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                if let postProcessedText = latestPostProcessedText {
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

                                        Text(postProcessedText)
                                            .foregroundStyle(.primary)
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
                                                Button {
                                                    withAnimation(.spring(duration: 0.4)) {
                                                        isSegmentsExpanded.toggle()
                                                    }
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Text(isSegmentsExpanded ? "Hide Timeline" : "Show Timeline")
                                                        Image(systemName: "chevron.down")
                                                            .rotationEffect(.degrees(isSegmentsExpanded ? 180 : 0))
                                                    }
                                                    .font(.caption.bold())
                                                    .foregroundStyle(Color.accentColor)
                                                }
                                                .buttonStyle(.plain)
                                                .padding(.top, 2)

                                                if isSegmentsExpanded {
                                                    TranscriptionDetailView(segments: segments)
                                                        .transition(.move(edge: .top).combined(with: .opacity))
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    Text(transcription)
                                        .foregroundStyle(.primary)
                                        .lineLimit(isExpanded ? nil : 2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            withAnimation(.spring(duration: 0.3)) {
                                                isExpanded.toggle()
                                                if !isExpanded { isSegmentsExpanded = false }
                                            }
                                        }

                                    if isExpanded, let segments = recording.segments, !segments.isEmpty {
                                        Button {
                                            withAnimation(.spring(duration: 0.4)) {
                                                isSegmentsExpanded.toggle()
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(isSegmentsExpanded ? "Hide Transcription" : "Show Transcription")
                                                Image(systemName: "chevron.down")
                                                    .rotationEffect(.degrees(isSegmentsExpanded ? 180 : 0))
                                            }
                                            .font(.caption.bold())
                                            .foregroundStyle(Color.accentColor)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.top, 2)

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
                    case .failed:
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Transcription failed")
                                .foregroundStyle(.secondary)
                        }
                    case .pending:
                        Text("Pending...")
                                .italic()
                                .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }

            // Actions Column
            VStack(spacing: 6) {
                if (recording.transcriptionStatus == .completed || recording.transcriptionStatus == .streamingTranscription), let text = textForCopy, !text.isEmpty {
                    Button {
                        ClipboardService.shared.copyToClipboard(text)
                        withAnimation {
                            showCopyFeedback = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                showCopyFeedback = false
                            }
                        }
                    } label: {
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
        .glassRowStyle(isHovering: isHovering || isExpanded)
        .onHover { isHovering = $0 }

        .contextMenu {
            if let postProcessed = latestPostProcessedText {
                Button {
                    ClipboardService.shared.copyToClipboard(postProcessed)
                } label: {
                    Label("Copy Post-Processed", systemImage: "wand.and.stars")
                }
            }

            if let transcription = recording.transcription, !transcription.isEmpty {
                Button {
                    ClipboardService.shared.copyToClipboard(transcription)
                } label: {
                    Label("Copy Original", systemImage: "doc.on.doc")
                }
            }

            if !recording.isFileDeleted {
                Button {
                    onDeleteAudioOnly()
                } label: {
                    Label("Delete Audio Only", systemImage: "waveform.slash")
                }
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var playPauseButton: some View {
        Button {
            audioPlayer.togglePlay(url: recording.fileURL, recordingID: recording.id)
        } label: {
            Image(systemName: isCurrentPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(isCurrentPlaying ? Color.accentColor : .secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00"
    }
}
