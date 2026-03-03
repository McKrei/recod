import Testing
@testable import Recod

@Suite("Levenshtein Distance")
struct LevenshteinDistanceTests {
    
    @Test("Identical strings return distance 0")
    func identicalStringsReturnZero() {
        #expect("hello".levenshteinDistance(to: "hello") == 0)
    }
    
    @Test("Empty to empty returns 0")
    func emptyToEmptyReturnsZero() {
        #expect("".levenshteinDistance(to: "") == 0)
    }
    
    @Test("Empty to non-empty returns length")
    func emptyToNonEmptyReturnsLength() {
        #expect("".levenshteinDistance(to: "abc") == 3)
    }
    
    @Test("Non-empty to empty returns length")
    func nonEmptyToEmptyReturnsLength() {
        #expect("abc".levenshteinDistance(to: "") == 3)
    }
    
    @Test("Single substitution returns 1")
    func singleSubstitution() {
        #expect("cat".levenshteinDistance(to: "car") == 1)
    }
    
    @Test("Single insertion returns 1")
    func singleInsertion() {
        #expect("cat".levenshteinDistance(to: "cats") == 1)
    }
    
    @Test("Single deletion returns 1")
    func singleDeletion() {
        #expect("cats".levenshteinDistance(to: "cat") == 1)
    }
    
    @Test("Completely different strings of same length")
    func completelyDifferentSameLength() {
        #expect("abc".levenshteinDistance(to: "xyz") == 3)
    }
    
    @Test("Case sensitivity matters (ABC vs abc)")
    func caseSensitivity() {
        #expect("ABC".levenshteinDistance(to: "abc") == 3)
    }
    
    @Test("Unicode (Cyrillic) identical strings")
    func unicodeCyrillic() {
        #expect("привет".levenshteinDistance(to: "привет") == 0)
    }
    
    @Test("Unicode (Mixed) completely different")
    func unicodeMixed() {
        #expect("hello".levenshteinDistance(to: "хелло") == 5)
    }
    
    @Test("Strings with spaces (deletion)")
    func stringsWithSpaces() {
        #expect("hello world".levenshteinDistance(to: "helloworld") == 1)
    }
    
    @Test("Symmetry property (a -> b == b -> a)")
    func symmetry() {
        let a = "kitten"
        let b = "sitting"
        #expect(a.levenshteinDistance(to: b) == b.levenshteinDistance(to: a))
        #expect(a.levenshteinDistance(to: b) == 3)
    }
}
