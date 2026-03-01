import SwiftUI
import SwiftData

struct AddReplacementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var ruleToEdit: ReplacementRule?

    @State private var patterns: [String] = [""]
    @State private var replacementText = ""
    @State private var weight: Float = 1.5
    @State private var useFuzzyMatching: Bool = true

    var isEditing: Bool { ruleToEdit != nil }

    var body: some View {
        VStack(spacing: 20) {
            Text(isEditing ? "Edit Replacement" : "Add Replacement")
                .font(.headline)
                .padding(.top)

            Form {
                Section(header: Text("Target Word / Replacement").font(.headline)) {
                    TextField("E.g., OpenCode", text: $replacementText)
                        .labelsHidden()
                }
                
                Section(header: Text("Typo Patterns (Optional)").font(.caption)) {
                    ForEach($patterns.indices, id: \.self) { index in
                        HStack {
                            TextField("E.g., OpenCod", text: $patterns[index])
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

                Section(header: Text("Advanced").font(.caption)) {
                    Toggle("Smart Fuzzy Matching", isOn: $useFuzzyMatching)
                        .toggleStyle(.switch)
                        .help("Automatically matches minor typos and phonetic variations.")
                    
                    Picker("Priority Weight", selection: $weight) {
                        Text("Low").tag(Float(1.0))
                        Text("Normal").tag(Float(1.5))
                        Text("High").tag(Float(2.0))
                    }
                    .pickerStyle(.segmented)
                    .help("How aggressively the AI should prefer this word.")
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
                .disabled(replacementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                weight = rule.weight
                useFuzzyMatching = rule.useFuzzyMatching
            }
        }
    }

    private func saveRule() {
        let cleanReplacement = replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanReplacement.isEmpty else { return }

        var validPatterns = patterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // If no patterns provided, use the replacement text as the primary pattern (Word Boosting scenario)
        if validPatterns.isEmpty {
            validPatterns.append(cleanReplacement)
        }

        let firstPattern = validPatterns[0]
        let additionalPatterns = Array(validPatterns.dropFirst())

        if let rule = ruleToEdit {
            rule.textToReplace = firstPattern
            rule.additionalIncorrectForms = additionalPatterns
            rule.replacementText = cleanReplacement
            rule.weight = weight
            rule.useFuzzyMatching = useFuzzyMatching
        } else {
            let rule = ReplacementRule(
                textToReplace: firstPattern,
                additionalIncorrectForms: additionalPatterns,
                replacementText: cleanReplacement,
                weight: weight,
                useFuzzyMatching: useFuzzyMatching
            )
            modelContext.insert(rule)
        }
        dismiss()
    }
}
