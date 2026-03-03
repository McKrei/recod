import Testing
import Foundation
@testable import Recod

@Suite("TranscriptionFormatter")
struct TranscriptionFormatterTests {
    
    @Test("Removes startoftranscript token")
    func removesStartOfTranscript() {
        #expect(TranscriptionFormatter.cleanSpecialTokens("<|startoftranscript|>Hello") == "Hello")
    }
    
    @Test("Removes multiple WhisperKit tokens")
    func removesMultipleTokens() {
        #expect(TranscriptionFormatter.cleanSpecialTokens("<|en|><|transcribe|>Hello world<|endoftext|>") == "Hello world")
    }
    
    @Test("No tokens remains unchanged")
    func noTokensUnchanged() {
        #expect(TranscriptionFormatter.cleanSpecialTokens("Hello world") == "Hello world")
    }
    
    @Test("Empty string returns empty")
    func emptyStringReturnsEmpty() {
        #expect(TranscriptionFormatter.cleanSpecialTokens("") == "")
    }
    
    @Test("String with only tokens returns empty")
    func onlyTokensReturnsEmpty() {
        #expect(TranscriptionFormatter.cleanSpecialTokens("<|startoftranscript|><|en|><|endoftext|>") == "")
    }
    
    @Test("Trims whitespace around tokens")
    func trimsWhitespace() {
        #expect(TranscriptionFormatter.cleanSpecialTokens("  <|en|>  Hello  ") == "Hello")
    }
    
    @Test("Preserves regular angle brackets")
    func preservesNonTokenAngles() {
        #expect(TranscriptionFormatter.cleanSpecialTokens("3 < 5 and 5 > 3") == "3 < 5 and 5 > 3")
    }
    
    @Test("Preserves pipe without angle brackets")
    func pipeWithoutAngles() {
        #expect(TranscriptionFormatter.cleanSpecialTokens("Hello | world") == "Hello | world")
    }
    
    @Test("Preserves Unicode content")
    func unicodeContentPreserved() {
        #expect(TranscriptionFormatter.cleanSpecialTokens("<|ru|>Привет мир") == "Привет мир")
    }
    
    @Test("Removes tokens in the middle of text (like timestamps)")
    func tokensInMiddleOfText() {
        // Though cleanSpecialTokens trims the result, it doesn't trim spaces *between* words around the token.
        #expect(TranscriptionFormatter.cleanSpecialTokens("Hello<|0.00|> world<|2.50|> foo") == "Hello world foo")
    }
    
    @Test("Removes consecutive tokens with no space")
    func consecutiveTokensNoSpace() {
        #expect(TranscriptionFormatter.cleanSpecialTokens("<|en|><|transcribe|><|notimestamps|>Test") == "Test")
    }
}
