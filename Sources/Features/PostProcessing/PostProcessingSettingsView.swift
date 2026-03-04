import SwiftUI
import SwiftData

struct PostProcessingSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PostProcessingAction.createdAt, order: .reverse) private var actions: [PostProcessingAction]

    @State private var showingAddSheet = false
    @State private var actionToEdit: PostProcessingAction?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsHeaderView(
                    title: "Post-Processing Actions",
                    subtitle: "Run AI prompts on finished transcripts using OpenAI-compatible providers.",
                    systemImage: "wand.and.stars"
                ) {
                    Button(action: { showingAddSheet = true }) {
                        Label("Add Action", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                if actions.isEmpty {
                    ContentUnavailableView(
                        "No Actions Added",
                        systemImage: "wand.and.stars",
                        description: Text("Create your first action to transform transcripts automatically or on demand.")
                    )
                    .padding(.top, 40)
                } else {
                    VStack(spacing: AppTheme.spacing) {
                        ForEach(actions) { action in
                            ActionRowView(
                                action: action,
                                onAutoEnabledChange: { isEnabled in
                                    withAnimation {
                                        if isEnabled {
                                            for candidate in actions {
                                                candidate.isAutoEnabled = (candidate.id == action.id)
                                            }
                                        } else {
                                            action.isAutoEnabled = false
                                        }
                                        try? modelContext.save()
                                    }
                                },
                                onEdit: {
                                    actionToEdit = action
                                },
                                onDelete: {
                                    withAnimation {
                                        modelContext.delete(action)
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .padding(AppTheme.pagePadding)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddActionView(actionToEdit: nil)
        }
        .sheet(item: $actionToEdit) { action in
            AddActionView(actionToEdit: action)
        }
    }
}

#Preview {
    PostProcessingSettingsView()
        .modelContainer(for: PostProcessingAction.self, inMemory: true)
}
