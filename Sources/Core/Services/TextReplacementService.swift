import Foundation

struct TextReplacementService {
    static func applyReplacements(text: String, rules: [ReplacementRule]) -> String {
        var processedText = text

        // Sort rules by length of text to replace (descending) to avoid partial replacements issues
        // e.g. "Test" and "Te" - replace "Test" first
        let sortedRules = rules.sorted { $0.textToReplace.count > $1.textToReplace.count }

        for rule in sortedRules {
            let pattern = rule.textToReplace.trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = rule.replacementText

            if pattern.isEmpty { continue }

            // Case insensitive replacement
            if let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: pattern), options: .caseInsensitive) {
                let range = NSRange(location: 0, length: processedText.utf16.count)
                processedText = regex.stringByReplacingMatches(in: processedText, options: [], range: range, withTemplate: replacement)
            }
        }

        return processedText
    }
}
