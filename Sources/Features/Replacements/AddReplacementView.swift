import SwiftUI
import SwiftData

struct AddReplacementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var ruleToEdit: ReplacementRule?

    @State private var patterns: [String] = [""]
    @State private var replacementText = ""

    var isEditing: Bool { ruleToEdit != nil }

    var body: some View {
        VStack(spacing: 20) {
            Text(isEditing ? "Edit Replacement" : "Add Replacement")
                .font(.headline)
                .padding(.top)

            Form {
                Section("Patterns") {
                    ForEach($patterns.indices, id: \.self) { index in
                        HStack {
                            TextField("", text: $patterns[index])
                                .labelsHidden() // Ensure no implicit label spacing

                            if patterns.count > 1 {
                                Button(action: {
                                    patterns.remove(at: index)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if patterns.count < 50 {
                        Button(action: { patterns.append("") }) {
                            Text("Add Pattern")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .controlSize(.small)
                    }
                }

                Section("Replacement") {
                    TextField("", text: $replacementText)
                        .labelsHidden()
                }
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
                .disabled(patterns.allSatisfy { $0.isEmpty } || replacementText.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 450, height: 400) // Slightly taller for the list
        .background(.ultraThinMaterial)
        .onAppear {
            if let rule = ruleToEdit {
                patterns = [rule.textToReplace] + rule.additionalIncorrectForms
                replacementText = rule.replacementText
            }
        }
    }

    private func saveRule() {
        let validPatterns = patterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let firstPattern = validPatterns.first else { return }
        let additionalPatterns = Array(validPatterns.dropFirst())

        if let rule = ruleToEdit {
            rule.textToReplace = firstPattern
            rule.additionalIncorrectForms = additionalPatterns
            rule.replacementText = replacementText
        } else {
            let rule = ReplacementRule(
                textToReplace: firstPattern,
                additionalIncorrectForms: additionalPatterns,
                replacementText: replacementText
            )
            modelContext.insert(rule)
        }
        dismiss()
    }
}
