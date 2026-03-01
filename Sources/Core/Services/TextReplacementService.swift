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
        guard !rules.isEmpty else { return text }
        
        let exactRules = rules.filter { !$0.useFuzzyMatching }
        let fuzzyRules = rules.filter { $0.useFuzzyMatching }

        var processedText = text
        
        if !exactRules.isEmpty {
            processedText = applyExactMatches(text: processedText, rules: exactRules)
        }
        
        if !fuzzyRules.isEmpty {
            processedText = applyFuzzyMatches(text: processedText, rules: fuzzyRules)
        }

        return processedText
    }

    /// Applies exact regex-based replacements.
    private static func applyExactMatches(text: String, rules: [ReplacementRule]) -> String {
        var processedText = text
        
        struct FlatRule {
            let pattern: String
            let replacement: String
        }

        var flatExactRules: [FlatRule] = []
        for rule in rules {
            let patterns = [rule.textToReplace] + rule.additionalIncorrectForms
            for pattern in patterns {
                let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    flatExactRules.append(FlatRule(pattern: trimmed, replacement: rule.replacementText))
                }
            }
        }

        // Sort by pattern length descending to prevent partial match issues (e.g., matching "cat" inside "catalog")
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
        
        return processedText
    }

    /// Applies fuzzy matching replacements based on Levenshtein distance.
    private static func applyFuzzyMatches(text: String, rules: [ReplacementRule]) -> String {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        var newWords: [String] = []
        newWords.reserveCapacity(words.count)
        
        for word in words {
            let cleanWord = word.trimmingCharacters(in: .punctuationCharacters)
            if cleanWord.isEmpty { 
                newWords.append(word)
                continue 
            }
            
            var replaced = false
            
            for rule in rules {
                let patterns = [rule.textToReplace] + rule.additionalIncorrectForms
                for pattern in patterns {
                    let cleanPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanPattern.isEmpty else { continue }
                    
                    let distance = cleanWord.lowercased().levenshteinDistance(to: cleanPattern.lowercased())
                    
                    // Allowed distance threshold:
                    // length <= 3 : distance 0 (exact match)
                    // length 4-5  : distance 1
                    // length > 5  : distance 2
                    let threshold = cleanPattern.count <= 3 ? 0 : (cleanPattern.count <= 5 ? 1 : 2)
                    
                    if distance <= threshold {
                        // Preserve punctuation from the original word
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
        
        return newWords.joined(separator: " ")
    }
}
