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

        // Split rules into exact match (or regex) and fuzzy match
        var exactRules: [ReplacementRule] = []
        var fuzzyRules: [ReplacementRule] = []
        
        for rule in rules {
            if rule.useFuzzyMatching {
                fuzzyRules.append(rule)
            } else {
                exactRules.append(rule)
            }
        }

        // Apply Exact Rules First
        struct FlatRule {
            let pattern: String
            let replacement: String
        }

        var flatExactRules: [FlatRule] = []
        for rule in exactRules {
            let primary = rule.textToReplace.trimmingCharacters(in: .whitespacesAndNewlines)
            if !primary.isEmpty {
                flatExactRules.append(FlatRule(pattern: primary, replacement: rule.replacementText))
            }
            for additional in rule.additionalIncorrectForms {
                let trimmed = additional.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    flatExactRules.append(FlatRule(pattern: trimmed, replacement: rule.replacementText))
                }
            }
        }

        let sortedExactRules = flatExactRules.sorted { $0.pattern.count > $1.pattern.count }

        for rule in sortedExactRules {
            let pattern = rule.pattern
            let replacement = rule.replacement

            // Case insensitive exact/regex replacement
            if let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: pattern), options: .caseInsensitive) {
                let range = NSRange(location: 0, length: processedText.utf16.count)
                processedText = regex.stringByReplacingMatches(in: processedText, options: [], range: range, withTemplate: replacement)
            }
        }

        // Apply Fuzzy Rules
        if !fuzzyRules.isEmpty {
            let words = processedText.components(separatedBy: .whitespacesAndNewlines)
            var newWords: [String] = []
            
            for word in words {
                let cleanWord = word.trimmingCharacters(in: .punctuationCharacters)
                if cleanWord.isEmpty { 
                    newWords.append(word)
                    continue 
                }
                
                var replaced = false
                
                for rule in fuzzyRules {
                    let patterns = [rule.textToReplace] + rule.additionalIncorrectForms
                    for pattern in patterns {
                        let cleanPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleanPattern.isEmpty else { continue }
                        
                        // We only fuzzy match single words for now, or phrases if the length matches closely
                        let distance = cleanWord.lowercased().levenshteinDistance(to: cleanPattern.lowercased())
                        
                        // Allowed distance threshold:
                        // length <= 3 : distance 0 (exact match)
                        // length 4-5  : distance 1
                        // length > 5  : distance 2
                        let threshold = cleanPattern.count <= 3 ? 0 : (cleanPattern.count <= 5 ? 1 : 2)
                        
                        if distance <= threshold {
                            // Preserve punctuation
                            if let range = word.range(of: cleanWord) {
                                let newWord = word.replacingCharacters(in: range, with: rule.replacementText)
                                newWords.append(newWord)
                            } else {
                                newWords.append(rule.replacementText)
                            }
                            replaced = true
                            break
                        }
                    }
                    if replaced { break }
                }
                
                if !replaced {
                    newWords.append(word)
                }
            }
            
            processedText = newWords.joined(separator: " ")
        }

        return processedText
    }
}
