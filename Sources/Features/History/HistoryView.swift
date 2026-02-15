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
                .padding(.top, AppTheme.pagePadding)
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
