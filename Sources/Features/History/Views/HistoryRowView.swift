import SwiftUI
import SwiftData

struct HistoryRowView: View {
    let recording: Recording
    let audioPlayer: AudioPlayer
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var showCopyFeedback = false

    private var isCurrentPlaying: Bool {
        audioPlayer.currentRecordingID == recording.id && audioPlayer.isPlaying
    }

    var body: some View {
        HStack(alignment: isExpanded ? .top : .center, spacing: AppTheme.spacing) {
            playPauseButton
                .padding(.top, isExpanded ? 4 : 0)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(formatDuration(recording.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                Group {
                    switch recording.transcriptionStatus ?? .completed {
                    case .transcribing:
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Transcribing...")
                                .foregroundStyle(.secondary)
                        }
                    case .completed:
                        if let transcription = recording.transcription, !transcription.isEmpty {
                            Text(transcription)
                                .foregroundStyle(.primary)
                                .lineLimit(isExpanded ? nil : 2)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.spring(duration: 0.3)) {
                                        isExpanded.toggle()
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

                VStack(spacing: 8) {
                    if let transcription = recording.transcription, !transcription.isEmpty {
                        Button {
                            ClipboardService.shared.copyToClipboard(transcription)
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
                                .font(.system(size: 14))
                                .foregroundStyle(showCopyFeedback ? .green : .secondary)
                                .frame(width: 24, height: 24)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help("Copy Transcription")
                    }

                    DeleteIconButton(action: onDelete)
                }
                .padding(.top, isExpanded ? 4 : 0)
            }
            .glassRowStyle(isHovering: isHovering)
            .onHover { isHovering = $0 }
            .contextMenu {
                if let transcription = recording.transcription {
                    Button {
                        ClipboardService.shared.copyToClipboard(transcription)
                    } label: {
                        Label("Copy Transcription", systemImage: "doc.on.doc")
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
