import Foundation
import Testing
@testable import Recod

@Suite("String Blank Helpers")
struct StringBlankTests {
    @Test("trimmed removes surrounding whitespace and newlines")
    func trimmedRemovesOuterWhitespace() {
        #expect("  hello\n".trimmed() == "hello")
    }

    @Test("isBlank detects whitespace-only content")
    func isBlankDetectsWhitespaceOnlyStrings() {
        #expect(" \n\t ".isBlank)
        #expect(!"hello".isBlank)
    }

    @Test("nilIfBlank collapses blank strings and preserves trimmed content")
    func nilIfBlankNormalizesValues() {
        #expect("  ".nilIfBlank == nil)
        #expect("  value  ".nilIfBlank == "value")

        let missing: String? = nil
        let blank: String? = "\n  "
        let value: String? = "  kept  "

        #expect(missing.nilIfBlank == nil)
        #expect(blank.nilIfBlank == nil)
        #expect(value.nilIfBlank == "kept")
    }
}
