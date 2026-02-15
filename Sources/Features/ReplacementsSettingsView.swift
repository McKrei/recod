import SwiftUI
import SwiftData

struct ReplacementsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReplacementRule.createdAt, order: .reverse) private var rules: [ReplacementRule]

    @State private var showingAddSheet = false
    @State private var ruleToEdit: ReplacementRule?

    var body: some View {
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
                            ReplacementRowView(rule: rule, onEdit: {
                                ruleToEdit = rule
                            }, onDelete: {
                                deleteRule(rule)
                            })
                        }
                    }
                }
            }
            .padding(AppTheme.pagePadding)
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

struct ReplacementRowView: View {
    let rule: ReplacementRule
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 16) {

            // Text Content
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(rule.textToReplace)
                    .font(.body)
                    .foregroundStyle(.secondary)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(rule.replacementText)
                    .font(.body)
                    .bold()
                    .foregroundStyle(.primary)

                Spacer()
            }

            // Actions
            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundStyle(isHovering ? .primary : .secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit Rule")

                DeleteIconButton(action: onDelete)
            }
            .opacity(isHovering ? 1.0 : 0.6)
        }
        .glassRowStyle(isHovering: isHovering)
        .onHover { isHovering = $0 }
    }
}


struct AddReplacementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var ruleToEdit: ReplacementRule?

    @State private var originalText = ""
    @State private var replacementText = ""

    var isEditing: Bool { ruleToEdit != nil }

    var body: some View {
        VStack(spacing: 20) {
            Text(isEditing ? "Edit Replacement" : "Add Replacement")
                .font(.headline)
                .padding(.top)

            Form {
                TextField("Original Text (Incorrect)", text: $originalText)
                TextField("Replacement (Correct)", text: $replacementText)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveRule()
                }
                .buttonStyle(.borderedProminent)
                .disabled(originalText.isEmpty || replacementText.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 400, height: 250)
        .background(.ultraThinMaterial)
        .onAppear {
            if let rule = ruleToEdit {
                originalText = rule.textToReplace
                replacementText = rule.replacementText
            }
        }
    }

    private func saveRule() {
        if let rule = ruleToEdit {
            rule.textToReplace = originalText
            rule.replacementText = replacementText
        } else {
            let rule = ReplacementRule(
                textToReplace: originalText,
                replacementText: replacementText
            )
            modelContext.insert(rule)
        }
        dismiss()
    }
}
