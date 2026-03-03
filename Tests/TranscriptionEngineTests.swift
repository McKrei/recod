import Testing
import Foundation
@testable import Recod

@Suite("TranscriptionEngine")
struct TranscriptionEngineTests {
    
    @Test("All cases are present")
    func allCasesCount() {
        #expect(TranscriptionEngine.allCases.count == 2)
    }
    
    @Test("Raw values match expected strings")
    func rawValues() {
        #expect(TranscriptionEngine.whisperKit.rawValue == "whisperKit")
        #expect(TranscriptionEngine.parakeet.rawValue == "parakeet")
    }
    
    @Test("Initialization from valid raw value")
    func initFromRawValue() {
        #expect(TranscriptionEngine(rawValue: "whisperKit") == .whisperKit)
        #expect(TranscriptionEngine(rawValue: "parakeet") == .parakeet)
    }
    
    @Test("Initialization from invalid raw value returns nil")
    func invalidRawValueReturnsNil() {
        #expect(TranscriptionEngine(rawValue: "invalid") == nil)
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let whisperData = try encoder.encode(TranscriptionEngine.whisperKit)
        let decodedWhisper = try decoder.decode(TranscriptionEngine.self, from: whisperData)
        #expect(decodedWhisper == .whisperKit)
        
        let parakeetData = try encoder.encode(TranscriptionEngine.parakeet)
        let decodedParakeet = try decoder.decode(TranscriptionEngine.self, from: parakeetData)
        #expect(decodedParakeet == .parakeet)
    }
    
    @Test("Display names are correct")
    func displayNames() {
        #expect(TranscriptionEngine.whisperKit.displayName == "WhisperKit")
        #expect(TranscriptionEngine.parakeet.displayName == "Parakeet V3")
    }
    
    @Test("Descriptions are correct")
    func descriptions() {
        #expect(TranscriptionEngine.whisperKit.description.contains("OpenAI Whisper"))
        #expect(TranscriptionEngine.parakeet.description.contains("NVIDIA Parakeet"))
    }
    
    @Test("Identifiable ID matches raw value")
    func identifiableId() {
        #expect(TranscriptionEngine.whisperKit.id == "whisperKit")
        #expect(TranscriptionEngine.parakeet.id == "parakeet")
    }
    
    @Test("Icon names are correct")
    func iconNames() {
        #expect(TranscriptionEngine.whisperKit.iconName == "waveform.circle")
        #expect(TranscriptionEngine.parakeet.iconName == "cpu")
    }
}
