import SwiftUI
import SwiftData

struct HistoryRowView: View {
    let recording: Recording
    let audioPlayer: AudioPlayer
    let onDelete: () -> Void
    let onDeleteAudioOnly: () -> Void
    let onRetranscribe: () -> Void
    let onRunPostProcessing: (PostProcessingAction) -> Void

    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var isSegmentsExpanded = false
    @State private var showCopyFeedback = false

    @Query(sort: \PostProcessingAction.sortOrder)
    private var postProcessingActions: [PostProcessingAction]

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

    private var transcriptionStatus: Recording.TranscriptionStatus {
        recording.transcriptionStatus ?? .completed
    }

    private var canRunPostProcessing: Bool {
        transcriptionStatus == .completed &&
        recording.transcription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        !postProcessingActions.isEmpty
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
                HistoryRowHeader(
                    createdAt: recording.createdAt,
                    durationText: formatDuration(recording.duration),
                    canRunPostProcessing: canRunPostProcessing,
                    postProcessingActions: postProcessingActions,
                    latestActionName: latestPostProcessedResult?.actionName,
                    onRunPostProcessing: onRunPostProcessing
                )

                HistoryRowContent(
                    recording: recording,
                    transcriptionStatus: transcriptionStatus,
                    latestPostProcessedResult: latestPostProcessedResult,
                    latestPostProcessedText: latestPostProcessedText,
                    textForCopy: textForCopy,
                    onCancelRetranscribe: {
                        RecordingOrchestrator.shared.cancelRetranscribe(recording: recording)
                    },
                    isExpanded: $isExpanded,
                    isSegmentsExpanded: $isSegmentsExpanded
                )
            }

            HistoryRowActions(
                transcriptionStatus: transcriptionStatus,
                textToCopy: textForCopy,
                showCopyFeedback: showCopyFeedback,
                onCopy: copyCurrentText,
                onDelete: onDelete
            )
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

                Button {
                    onRetranscribe()
                } label: {
                    Label("Retranscribe", systemImage: "arrow.trianglehead.2.clockwise.rotate.90.circle")
                }

                if recording.transcriptionStatus == .queued {
                    Button(role: .destructive) {
                        RecordingOrchestrator.shared.cancelRetranscribe(recording: recording)
                    } label: {
                        Label("Cancel Retranscription", systemImage: "xmark.circle")
                    }
                }
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func copyCurrentText() {
        guard let text = textForCopy, !text.isEmpty else { return }

        ClipboardService.shared.copyToClipboard(text)
        withAnimation {
            showCopyFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopyFeedback = false
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
