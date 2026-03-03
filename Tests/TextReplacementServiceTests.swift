import Testing
import Foundation
import SwiftData
@testable import Recod

@Suite("TextReplacementService")
struct TextReplacementServiceTests {
    
    // MARK: - Helper to create rules in memory
    
    @MainActor
    private func makeRule(
        textToReplace: String,
        replacementText: String,
        additionalForms: [String] = [],
        useFuzzyMatching: Bool = true,
        weight: Float = 1.5,
        context: ModelContext
    ) -> ReplacementRule {
        let rule = ReplacementRule(
            textToReplace: textToReplace,
            additionalIncorrectForms: additionalForms,
            replacementText: replacementText,
            weight: weight,
            useFuzzyMatching: useFuzzyMatching
        )
        context.insert(rule)
        return rule
    }
    
    @MainActor
    private func withContext<T>(_ execute: (ModelContext) throws -> T) rethrows -> T {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: ReplacementRule.self, configurations: config)
        let context = ModelContext(container)
        return try execute(context)
    }
    
    // MARK: - Exact Matching (useFuzzyMatching = false)
    
    @Test("Empty rules array returns original text")
    @MainActor
    func emptyRulesReturnsText() {
        #expect(TextReplacementService.applyReplacements(text: "Hello", rules: []) == "Hello")
    }
    
    @Test("Exact match is case-insensitive")
    @MainActor
    func exactCaseInsensitive() {
        withContext { context in
            let rule = makeRule(textToReplace: "hello", replacementText: "Hi", useFuzzyMatching: false, context: context)
            #expect(TextReplacementService.applyReplacements(text: "hello World", rules: [rule]) == "Hi World")
            #expect(TextReplacementService.applyReplacements(text: "HELLO World", rules: [rule]) == "Hi World")
        }
    }
    
    @Test("Exact match multiple occurrences")
    @MainActor
    func exactMultipleOccurrences() {
        withContext { context in
            let rule = makeRule(textToReplace: "cat", replacementText: "dog", useFuzzyMatching: false, context: context)
            #expect(TextReplacementService.applyReplacements(text: "cat and cat", rules: [rule]) == "dog and dog")
        }
    }
    
    @Test("Exact matching applies longest patterns first to prevent partial overlaps")
    @MainActor
    func exactLongestFirst() {
        withContext { context in
            let rule1 = makeRule(textToReplace: "catalog", replacementText: "каталог", useFuzzyMatching: false, context: context)
            let rule2 = makeRule(textToReplace: "cat", replacementText: "кот", useFuzzyMatching: false, context: context)
            
            // Should match "catalog", not just "cat" inside it
            #expect(TextReplacementService.applyReplacements(text: "catalog", rules: [rule1, rule2]) == "каталог")
            #expect(TextReplacementService.applyReplacements(text: "catalog", rules: [rule2, rule1]) == "каталог")
        }
    }
    
    @Test("Exact match with additional forms")
    @MainActor
    func exactAdditionalForms() {
        withContext { context in
            let rule = makeRule(textToReplace: "color", replacementText: "цвет", additionalForms: ["colour"], useFuzzyMatching: false, context: context)
            #expect(TextReplacementService.applyReplacements(text: "colour is good", rules: [rule]) == "цвет is good")
        }
    }
    
    @Test("Exact match with empty textToReplace is ignored")
    @MainActor
    func exactEmptyTextToReplace() {
        withContext { context in
            let rule = makeRule(textToReplace: "", replacementText: "world", useFuzzyMatching: false, context: context)
            #expect(TextReplacementService.applyReplacements(text: "hello", rules: [rule]) == "hello")
        }
    }
    
    @Test("Exact match with whitespace-only pattern is ignored")
    @MainActor
    func exactWhitespaceOnlyPattern() {
        withContext { context in
            let rule = makeRule(textToReplace: "   ", replacementText: "world", useFuzzyMatching: false, context: context)
            #expect(TextReplacementService.applyReplacements(text: "hello", rules: [rule]) == "hello")
        }
    }
    
    @Test("Exact match escapes special regex characters")
    @MainActor
    func exactSpecialRegexChars() {
        withContext { context in
            let rule = makeRule(textToReplace: "$100", replacementText: "$200", useFuzzyMatching: false, context: context)
            #expect(TextReplacementService.applyReplacements(text: "price is $100", rules: [rule]) == "price is $200")
        }
    }
    
    // MARK: - Fuzzy Matching (useFuzzyMatching = true)
    
    @Test("Fuzzy match with distance 0")
    @MainActor
    func fuzzyExactMatch() {
        withContext { context in
            let rule = makeRule(textToReplace: "hello", replacementText: "Hi", useFuzzyMatching: true, context: context)
            #expect(TextReplacementService.applyReplacements(text: "hello world", rules: [rule]) == "Hi world")
        }
    }
    
    @Test("Fuzzy match within threshold (1 error)")
    @MainActor
    func fuzzyOneCharDifference() {
        withContext { context in
            let rule = makeRule(textToReplace: "claude code", replacementText: "Claude Code", useFuzzyMatching: true, context: context)
            // claud -> 1 error
            #expect(TextReplacementService.applyReplacements(text: "claud code", rules: [rule]) == "Claude Code")
        }
    }
    
    @Test("Fuzzy match beyond threshold is not replaced")
    @MainActor
    func fuzzyBeyondThreshold() {
        withContext { context in
            let rule = makeRule(textToReplace: "hello", replacementText: "Hi", useFuzzyMatching: true, context: context)
            // hello (len 5, thresh 1). "xxxxx" distance is 5
            #expect(TextReplacementService.applyReplacements(text: "xxxxx", rules: [rule]) == "xxxxx")
        }
    }
    
    @Test("Fuzzy multi-word pattern")
    @MainActor
    func fuzzyMultiWordPattern() {
        withContext { context in
            let rule = makeRule(textToReplace: "claude code", replacementText: "Claude Code", useFuzzyMatching: true, context: context)
            // claud cide is 2 errors from "claude code". Length=11, thresh=3.
            #expect(TextReplacementService.applyReplacements(text: "claud cide is great", rules: [rule]) == "Claude Code is great")
        }
    }
    
    @Test("Fuzzy ASR merge (window size pw-1)")
    @MainActor
    func fuzzyASRMerge() {
        withContext { context in
            let rule = makeRule(textToReplace: "claude code", replacementText: "Claude Code", useFuzzyMatching: true, context: context)
            // Original: 2 words. ASR: 1 word ("claudecode"). Length 11, thresh 3. Distance 1 (space missing).
            #expect(TextReplacementService.applyReplacements(text: "claudecode is nice", rules: [rule]) == "Claude Code is nice")
        }
    }
    
    @Test("Fuzzy ASR split (window size pw+1)")
    @MainActor
    func fuzzyASRSplit() {
        withContext { context in
            let rule = makeRule(textToReplace: "claude code", replacementText: "Claude Code", useFuzzyMatching: true, context: context)
            // Original: 2 words. ASR: 3 words. Length 11, thresh 3. Distance 1 (extra space).
            #expect(TextReplacementService.applyReplacements(text: "clau de code rocks", rules: [rule]) == "Claude Code rocks")
        }
    }
    
    @Test("Fuzzy preserves punctuation")
    @MainActor
    func fuzzyPunctuationPreserved() {
        withContext { context in
            let rule = makeRule(textToReplace: "Sparkletini", replacementText: "Sparkletini", useFuzzyMatching: true, context: context)
            // Pattern has 1 word. Text is "...sparkletini,".
            #expect(TextReplacementService.applyReplacements(text: "...sparkletini, is", rules: [rule]) == "...Sparkletini, is")
        }
    }
    
    @Test("Fuzzy empty text")
    @MainActor
    func fuzzyEmptyText() {
        withContext { context in
            let rule = makeRule(textToReplace: "hello", replacementText: "Hi", useFuzzyMatching: true, context: context)
            #expect(TextReplacementService.applyReplacements(text: "", rules: [rule]) == "")
        }
    }
    
    @Test("Fuzzy text with single word")
    @MainActor
    func fuzzySingleWord() {
        withContext { context in
            let rule = makeRule(textToReplace: "hello", replacementText: "Hello", useFuzzyMatching: true, context: context)
            #expect(TextReplacementService.applyReplacements(text: "helo", rules: [rule]) == "Hello")
        }
    }
    
    @Test("Fuzzy pattern longer than text")
    @MainActor
    func fuzzyPatternLongerThanText() {
        withContext { context in
            let rule = makeRule(textToReplace: "hello world foo bar", replacementText: "X", useFuzzyMatching: true, context: context)
            #expect(TextReplacementService.applyReplacements(text: "hi", rules: [rule]) == "hi")
        }
    }
    
    // MARK: - Threshold Boundaries
    
    @Test("Threshold boundary: length 3 (0 errors allowed)")
    @MainActor
    func thresholdLength3() {
        withContext { context in
            let rule = makeRule(textToReplace: "cat", replacementText: "dog", useFuzzyMatching: true, context: context)
            #expect(TextReplacementService.applyReplacements(text: "cat", rules: [rule]) == "dog") // dist 0
            #expect(TextReplacementService.applyReplacements(text: "car", rules: [rule]) == "car") // dist 1 > 0
        }
    }
    
    @Test("Threshold boundary: length 4 (1 error allowed)")
    @MainActor
    func thresholdLength4() {
        withContext { context in
            let rule = makeRule(textToReplace: "word", replacementText: "bird", useFuzzyMatching: true, context: context)
            #expect(TextReplacementService.applyReplacements(text: "ward", rules: [rule]) == "bird") // dist 1
            #expect(TextReplacementService.applyReplacements(text: "wark", rules: [rule]) == "wark") // dist 2 > 1
        }
    }
    
    @Test("Threshold boundary: length 6 (2 errors allowed)")
    @MainActor
    func thresholdLength6() {
        withContext { context in
            let rule = makeRule(textToReplace: "kitten", replacementText: "cat", useFuzzyMatching: true, context: context)
            #expect(TextReplacementService.applyReplacements(text: "kitte", rules: [rule]) == "cat") // dist 1
            #expect(TextReplacementService.applyReplacements(text: "sitten", rules: [rule]) == "cat") // dist 1
            #expect(TextReplacementService.applyReplacements(text: "xxxxen", rules: [rule]) == "xxxxen") // dist 4 > 2
        }
    }
    
    @Test("Threshold boundary: length 9 (3 errors allowed)")
    @MainActor
    func thresholdLength9() {
        withContext { context in
            let rule = makeRule(textToReplace: "something", replacementText: "X", useFuzzyMatching: true, context: context)
            #expect(TextReplacementService.applyReplacements(text: "somethin", rules: [rule]) == "X") // dist 1
            #expect(TextReplacementService.applyReplacements(text: "xxxxthing", rules: [rule]) == "xxxxthing") // dist 4 > 3
        }
    }
    
    @Test("Threshold boundary: length 13 (4 errors allowed)")
    @MainActor
    func thresholdLength13() {
        withContext { context in
            let rule = makeRule(textToReplace: "international", replacementText: "X", useFuzzyMatching: true, context: context)
            #expect(TextReplacementService.applyReplacements(text: "internationa", rules: [rule]) == "X") // dist 1
        }
    }
    
    // MARK: - Combined
    
    @Test("Exact rules run before fuzzy rules")
    @MainActor
    func exactThenFuzzy() {
        withContext { context in
            let ruleExact = makeRule(textToReplace: "cat", replacementText: "dog", useFuzzyMatching: false, context: context)
            let ruleFuzzy = makeRule(textToReplace: "dog and bird", replacementText: "pets", useFuzzyMatching: true, context: context)
            
            // "cat and bird" --(exact)--> "dog and bird" --(fuzzy)--> "pets"
            #expect(TextReplacementService.applyReplacements(text: "cat and bird", rules: [ruleExact, ruleFuzzy]) == "pets")
        }
    }
    
    @Test("Fuzzy avoids double processing")
    @MainActor
    func noDoubleProcessing() {
        withContext { context in
            let rule = makeRule(textToReplace: "foo", replacementText: "foo foo", useFuzzyMatching: true, context: context)
            // "foo bar" -> "foo foo bar". It should not keep expanding "foo" into infinity.
            #expect(TextReplacementService.applyReplacements(text: "foo bar", rules: [rule]) == "foo foo bar")
        }
    }
    
    @Test("Multiple fuzzy rules pick the longest match")
    @MainActor
    func multipleRulesLongestFirst() {
        withContext { context in
            let ruleShort = makeRule(textToReplace: "hello", replacementText: "A", useFuzzyMatching: true, context: context)
            let ruleLong = makeRule(textToReplace: "hello world", replacementText: "B", useFuzzyMatching: true, context: context)
            
            // Should pick B
            #expect(TextReplacementService.applyReplacements(text: "hello world foo", rules: [ruleShort, ruleLong]) == "B foo")
            #expect(TextReplacementService.applyReplacements(text: "hello world foo", rules: [ruleLong, ruleShort]) == "B foo")
        }
    }
}
