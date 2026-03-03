import Foundation

/// A service responsible for applying text replacement rules to strings.
///
/// This service handles case-insensitive exact replacements and N-gram fuzzy replacements,
/// prioritizing longer patterns to prevent partial match issues.
struct TextReplacementService {
    
    // MARK: - Public API
    
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
    
    // MARK: - Exact Matching
    
    private struct ExactPattern {
        let pattern: String
        let replacement: String
    }

    /// Applies exact regex-based replacements.
    private static func applyExactMatches(text: String, rules: [ReplacementRule]) -> String {
        let patterns = buildExactPatterns(from: rules)
        var processedText = text
        
        for rule in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: NSRegularExpression.escapedPattern(for: rule.pattern),
                options: .caseInsensitive
            ) else { continue }
            
            let escapedReplacement = NSRegularExpression.escapedTemplate(for: rule.replacement)
            
            let range = NSRange(location: 0, length: processedText.utf16.count)
            processedText = regex.stringByReplacingMatches(
                in: processedText,
                options: [],
                range: range,
                withTemplate: escapedReplacement
            )
        }
        
        return processedText
    }
    
    private static func buildExactPatterns(from rules: [ReplacementRule]) -> [ExactPattern] {
        var exactPatterns: [ExactPattern] = []
        for rule in rules {
            let allForms = [rule.textToReplace] + rule.additionalIncorrectForms
            for form in allForms {
                let trimmed = form.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    exactPatterns.append(ExactPattern(pattern: trimmed, replacement: rule.replacementText))
                }
            }
        }
        // Sort by pattern length descending to prevent partial match issues (e.g., matching "cat" inside "catalog")
        return exactPatterns.sorted { $0.pattern.count > $1.pattern.count }
    }

    // MARK: - Fuzzy Matching
    
    private struct FuzzyPattern {
        let cleanPattern: String
        let replacement: String
        let wordCount: Int
    }
    
    /// Applies fuzzy matching replacements based on Levenshtein distance.
    /// Supports N-gram (multi-word) matching via sliding window.
    private static func applyFuzzyMatches(text: String, rules: [ReplacementRule]) -> String {
        let patterns = buildFuzzyPatterns(from: rules)
        var words = text.components(separatedBy: " ")
        if words.isEmpty { return text }
        
        var i = 0
        while i < words.count {
            if let match = findMatchInWindow(startingAt: i, words: words, patterns: patterns) {
                // Replace the matched words window with the replacement text
                words.replaceSubrange(i..<i+match.windowSize, with: [match.replacementToken])
            }
            // Move forward (if replaced, we skip the new replacement string to avoid double-processing)
            i += 1
        }
        
        return words.joined(separator: " ")
    }
    
    private static func buildFuzzyPatterns(from rules: [ReplacementRule]) -> [FuzzyPattern] {
        var patterns: [FuzzyPattern] = []
        for rule in rules {
            let allForms = [rule.textToReplace] + rule.additionalIncorrectForms
            for form in allForms {
                let clean = form.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { continue }
                
                let cleanLowercased = clean.lowercased()
                patterns.append(FuzzyPattern(
                    cleanPattern: cleanLowercased,
                    replacement: rule.replacementText,
                    wordCount: cleanLowercased.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
                ))
            }
        }
        
        // Sort by pattern length descending to match longest phrases first, avoiding partial overlaps.
        return patterns.sorted { $0.cleanPattern.count > $1.cleanPattern.count }
    }
    
    /// Result of a successful window match
    private struct WindowMatch {
        let windowSize: Int
        let replacementToken: String
    }
    
    /// Checks all patterns against potential N-gram windows starting at index `i`.
    private static func findMatchInWindow(startingAt i: Int, words: [String], patterns: [FuzzyPattern]) -> WindowMatch? {
        for pattern in patterns {
            let pw = pattern.wordCount
            
            // We check N-grams of sizes: exact word count, fewer words (ASR merged), more words (ASR split).
            var windowSizes = [pw]
            if pw > 1 { windowSizes.append(pw - 1) }
            windowSizes.append(pw + 1)
            
            for w in windowSizes {
                guard i + w <= words.count else { continue }
                
                let windowWords = Array(words[i..<i+w])
                let joinedWindow = windowWords.joined(separator: " ")
                
                let cleanJoined = joinedWindow
                    .trimmingCharacters(in: .punctuationCharacters)
                    .lowercased()
                
                guard !cleanJoined.isEmpty else { continue }
                
                let distance = cleanJoined.levenshteinDistance(to: pattern.cleanPattern)
                let threshold = calculateDistanceThreshold(forLength: pattern.cleanPattern.count)
                
                if distance <= threshold {
                    // Match found! Preserve original punctuation on edges.
                    let replacementWord = preservePunctuation(originalWords: windowWords, replacementText: pattern.replacement)
                    return WindowMatch(windowSize: w, replacementToken: replacementWord)
                }
            }
        }
        return nil
    }
    
    /// Calculates the allowed Levenshtein distance based on pattern length.
    private static func calculateDistanceThreshold(forLength count: Int) -> Int {
        switch count {
        case 0...3: return 0
        case 4...5: return 1
        case 6...8: return 2
        case 9...12: return 3
        default: return 4
        }
    }
    
    /// Wraps the replacement text in the leading and trailing punctuation of the original window.
    private static func preservePunctuation(originalWords: [String], replacementText: String) -> String {
        guard let firstWord = originalWords.first, let lastWord = originalWords.last else {
            return replacementText
        }
        
        let prefix = firstWord.prefix(while: { $0.isPunctuation })
        let suffixChars = lastWord.reversed().prefix(while: { $0.isPunctuation }).reversed()
        let suffix = String(suffixChars)
        
        return String(prefix) + replacementText + suffix
    }
}
