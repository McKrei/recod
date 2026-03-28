import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioPlayer.self) private var audioPlayer
    @EnvironmentObject private var appState: AppState

    @Query(sort: \Recording.createdAt, order: .reverse)
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
                            HistoryRowView(
                                recording: recording,
                                audioPlayer: audioPlayer,
                                onDelete: { deleteRecording(recording) },
                                onDeleteAudioOnly: { deleteAudioOnly(recording) },
                                onRetranscribe: { retranscribeRecording(recording) },
                                onCancelRetranscribe: { cancelRetranscription(recording) },
                                onRunPostProcessing: { action in
                                    runPostProcessing(recording, action: action)
                                },
                                onCopyText: copyText
                            )
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

        // Remove file from disk if it exists
        if !recording.isFileDeleted {
            try? FileManager.default.removeItem(at: recording.fileURL)
        }

        // Completely delete the record from DB
        modelContext.delete(recording)
    }

    private func deleteAudioOnly(_ recording: Recording) {
        if audioPlayer.currentRecordingID == recording.id {
            audioPlayer.stop()
        }

        // Remove file from disk if it exists
        if !recording.isFileDeleted {
            try? FileManager.default.removeItem(at: recording.fileURL)
            recording.isFileDeleted = true
        }

        // If there's no transcription, delete the entire block
        if recording.transcription.nilIfBlank == nil {
            modelContext.delete(recording)
        }
    }

    private func deleteAllFiles() {
        // Stop playback if playing one of the recordings
        if let currentID = audioPlayer.currentRecordingID, recordings.contains(where: { $0.id == currentID }) {
            audioPlayer.stop()
        }

        withAnimation {
            for recording in recordings where !recording.isFileDeleted {
                // Delete file
                try? FileManager.default.removeItem(at: recording.fileURL)
                // Update model
                recording.isFileDeleted = true
                
                // If there's no transcription, delete the entire block
                if recording.transcription.nilIfBlank == nil {
                    modelContext.delete(recording)
                }
            }
        }
    }

    private func retranscribeRecording(_ recording: Recording) {
        appState.retranscribe(recording)
    }

    private func cancelRetranscription(_ recording: Recording) {
        appState.cancelRetranscribe(recording)
    }

    private func runPostProcessing(_ recording: Recording, action: PostProcessingAction) {
        appState.runManualPostProcessing(recording: recording, action: action)
    }

    private func copyText(_ text: String) {
        appState.copyTextToClipboard(text)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Recording.self, PostProcessingAction.self, configurations: config)

    let samples = [
        Recording(createdAt: .now, duration: 125, transcription: "Hello world, this is a test recording.", transcriptionStatus: .completed, filename: "rec1.m4a"),
        Recording(createdAt: .now.addingTimeInterval(-3600), duration: 45, transcription: nil, transcriptionStatus: .transcribing, filename: "rec2.m4a"),
        Recording(createdAt: .now.addingTimeInterval(-86400), duration: 320, transcription: "Long meeting notes about the project status.", transcriptionStatus: .completed, filename: "rec3.m4a")
    ]

    for sample in samples {
        container.mainContext.insert(sample)
    }

    let previewActions = [
        PostProcessingAction(
            name: "Summarize",
            prompt: "Summarize transcript:\n${output}",
            providerID: "preview-provider",
            modelID: "preview-model",
            sortOrder: 0
        ),
        PostProcessingAction(
            name: "Cleanup",
            prompt: "Clean up transcript formatting:\n${output}",
            providerID: "preview-provider",
            modelID: "preview-model",
            sortOrder: 1
        )
    ]

    for action in previewActions {
        container.mainContext.insert(action)
    }

    return HistoryView()
        .modelContainer(container)
        .environment(AudioPlayer())
        .frame(width: 500, height: 600)
}
