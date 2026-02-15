import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioPlayer.self) private var audioPlayer

    // Show only recordings where file is NOT deleted
    @Query(filter: #Predicate<Recording> { !$0.isFileDeleted }, sort: \Recording.createdAt, order: .reverse)
    private var recordings: [Recording]

    @State private var showDeleteAllAlert = false

    var body: some View {
        VStack(spacing: 0) {
            if !recordings.isEmpty {
                HistoryStatsHeader(
                    recordings: recordings,
                    onDeleteAll: { showDeleteAllAlert = true }
                )
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, AppTheme.padding)
                .padding(.bottom, AppTheme.spacing)
            }

            if recordings.isEmpty {
                ContentUnavailableView(
                    "No Recordings",
                    systemImage: "mic.slash",
                    description: Text("Your recording history will appear here.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: AppTheme.spacing) {
                        ForEach(recordings) { recording in
                            HistoryRowView(recording: recording, audioPlayer: audioPlayer) {
                                deleteRecording(recording)
                            }
                        }
                    }
                    .padding(AppTheme.pagePadding)
                    // Remove top padding because header has bottom padding
                    .padding(.top, 0)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 400, minHeight: 500)
        .background(Color.clear)
        .alert("Delete All Audio Files?", isPresented: $showDeleteAllAlert) {
            Button("Delete All", role: .destructive) {
                deleteAllFiles()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all audio files from your disk to free up space. Transcriptions will remain saved in your history.")
        }
    }

    private func deleteRecording(_ recording: Recording) {
        if audioPlayer.currentRecordingID == recording.id {
            audioPlayer.stop()
        }

        // Remove file from disk
        try? FileManager.default.removeItem(at: recording.fileURL)

        // Mark as deleted in DB instead of removing the record
        recording.isFileDeleted = true
        // Optional: clear file URL path or keep it for reference?
        // We keep filename so we know what it was.
    }

    private func deleteAllFiles() {
        // Stop playback if playing one of the recordings
        if let currentID = audioPlayer.currentRecordingID, recordings.contains(where: { $0.id == currentID }) {
            audioPlayer.stop()
        }

        withAnimation {
            for recording in recordings {
                // Delete file
                try? FileManager.default.removeItem(at: recording.fileURL)
                // Update model
                recording.isFileDeleted = true
            }
        }
    }
}

struct HistoryStatsHeader: View {
    let recordings: [Recording]
    let onDeleteAll: () -> Void

    @State private var totalSize: Int64 = 0

    var body: some View {
        GroupBox {
            HStack {
                StatItem(label: "Files", value: "\(recordings.count)")

                Divider()
                    .frame(height: 20)

                StatItem(label: "Total Size", value: ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))

                Spacer()

                Button(role: .destructive, action: onDeleteAll) {
                    Text("Delete All Files")
                }
                .controlSize(.small)
            }
        }
        .groupBoxStyle(GlassGroupBoxStyle())
        .onAppear(perform: calculateSize)
        .onChange(of: recordings, calculateSize)
    }

    private func calculateSize() {
        // Access model properties on MainActor
        let fileURLs = recordings.map { $0.fileURL }

        Task.detached(priority: .background) {
            var size: Int64 = 0
            for url in fileURLs {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let fileSize = attributes[.size] as? Int64 {
                    size += fileSize
                }
            }
            await MainActor.run {
                self.totalSize = size
            }
        }
    }
}

struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

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

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Recording.self, configurations: config)

    let samples = [
        Recording(createdAt: .now, duration: 125, transcription: "Hello world, this is a test recording.", transcriptionStatus: .completed, filename: "rec1.m4a"),
        Recording(createdAt: .now.addingTimeInterval(-3600), duration: 45, transcription: nil, transcriptionStatus: .transcribing, filename: "rec2.m4a"),
        Recording(createdAt: .now.addingTimeInterval(-86400), duration: 320, transcription: "Long meeting notes about the project status.", transcriptionStatus: .completed, filename: "rec3.m4a")
    ]

    for sample in samples {
        container.mainContext.insert(sample)
    }

    return HistoryView()
        .modelContainer(container)
        .environment(AudioPlayer())
        .frame(width: 500, height: 600)
}
