import SwiftUI
import SwiftData

struct ReplacementsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReplacementRule.createdAt, order: .reverse) private var rules: [ReplacementRule]

    @State private var showingAddSheet = false
    @State private var ruleToEdit: ReplacementRule?

    var body: some View {
        GeometryReader { geometry in
            let containerWidth = geometry.size.width - (AppTheme.pagePadding * 2)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header
                    SettingsHeaderView(
                        title: "Text Replacements",
                        subtitle: "Automatically replace text in transcriptions. Case insensitive.",
                        systemImage: "text.badge.checkmark"
                    ) {
                        Button(action: { showingAddSheet = true }) {
                            Label("Add Rule", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }

                    // Rules List
                    if rules.isEmpty {
                        ContentUnavailableView(
                            "No Replacements",
                            systemImage: "text.badge.checkmark",
                            description: Text("Add rules to fix common transcription errors.")
                        )
                        .padding(.top, 40)
                    } else {
                        VStack(spacing: AppTheme.spacing) {
                            ForEach(rules) { rule in
                                ReplacementRowView(
                                    rule: rule,
                                    containerWidth: containerWidth,
                                    onEdit: {
                                        ruleToEdit = rule
                                    },
                                    onDelete: {
                                        deleteRule(rule)
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(AppTheme.pagePadding)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddReplacementView(ruleToEdit: nil)
        }
        .sheet(item: $ruleToEdit) { rule in
            AddReplacementView(ruleToEdit: rule)
        }
    }

    private func deleteRule(_ rule: ReplacementRule) {
        withAnimation {
            modelContext.delete(rule)
        }
    }
}
