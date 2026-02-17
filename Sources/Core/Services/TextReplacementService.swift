import Foundation

/// A service responsible for applying text replacement rules to strings.
///
/// This service handles case-insensitive replacements and ensures that longer patterns
/// are prioritized to prevent partial match issues.
struct TextReplacementService {
    /// Applies the given replacement rules to the text.
    ///
    /// - Parameters:
    ///   - text: The original text to process.
    ///   - rules: The list of replacement rules to apply.
    /// - Returns: The text with all replacements applied.
    static func applyReplacements(text: String, rules: [ReplacementRule]) -> String {
        var processedText = text

        // Flatten rules into a list of (pattern, replacement) and sort by pattern length descending
        struct FlatRule {
            let pattern: String
            let replacement: String
        }

        var flatRules: [FlatRule] = []
        for rule in rules {
            let primary = rule.textToReplace.trimmingCharacters(in: .whitespacesAndNewlines)
            if !primary.isEmpty {
                flatRules.append(FlatRule(pattern: primary, replacement: rule.replacementText))
            }
            for additional in rule.additionalIncorrectForms {
                let trimmed = additional.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    flatRules.append(FlatRule(pattern: trimmed, replacement: rule.replacementText))
                }
            }
        }

        let sortedRules = flatRules.sorted { $0.pattern.count > $1.pattern.count }

        for rule in sortedRules {
            let pattern = rule.pattern
            let replacement = rule.replacement

            // Case insensitive replacement
            if let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: pattern), options: .caseInsensitive) {
                let range = NSRange(location: 0, length: processedText.utf16.count)
                processedText = regex.stringByReplacingMatches(in: processedText, options: [], range: range, withTemplate: replacement)
            }
        }

        return processedText
    }
}
