import Testing
import Foundation
@testable import Recod

@Suite("TranscriptionSegment & TranscriptionStatus")
struct TranscriptionSegmentTests {
    
    // MARK: - TranscriptionSegment Tests
    
    @Test("Initialization of TranscriptionSegment")
    func segmentInit() {
        let segment = TranscriptionSegment(start: 1.0, end: 2.5, text: "Hello")
        #expect(segment.start == 1.0)
        #expect(segment.end == 2.5)
        #expect(segment.text == "Hello")
    }
    
    @Test("Codable round-trip for TranscriptionSegment")
    func segmentCodableRoundTrip() throws {
        let original = TranscriptionSegment(start: 0.0, end: 1.2, text: "Testing")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TranscriptionSegment.self, from: data)
        
        #expect(decoded.start == original.start)
        #expect(decoded.end == original.end)
        #expect(decoded.text == original.text)
        #expect(decoded.id == original.id)
    }
    
    @Test("Identifiable conformance provides valid UUID")
    func segmentIdentifiable() {
        let segment = TranscriptionSegment(start: 0.0, end: 1.0, text: "Test")
        #expect(segment.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
    }
    
    @Test("Hashable: Same content but different IDs are not equal")
    func segmentHashableDifferentIds() {
        let segment1 = TranscriptionSegment(start: 0.0, end: 1.0, text: "Test")
        let segment2 = TranscriptionSegment(start: 0.0, end: 1.0, text: "Test")
        // Different generated UUIDs mean they are distinct objects
        #expect(segment1 != segment2)
        #expect(segment1.hashValue != segment2.hashValue)
    }
    
    @Test("Hashable: Same ID are equal")
    func segmentHashableSameId() {
        let id = UUID()
        let segment1 = TranscriptionSegment(id: id, start: 0.0, end: 1.0, text: "Test")
        let segment2 = TranscriptionSegment(id: id, start: 0.0, end: 1.0, text: "Test")
        #expect(segment1 == segment2)
        #expect(segment1.hashValue == segment2.hashValue)
    }
    
    // MARK: - Recording.TranscriptionStatus Tests
    
    @Test("TranscriptionStatus raw values")
    func statusRawValues() {
        #expect(Recording.TranscriptionStatus.pending.rawValue == "pending")
        #expect(Recording.TranscriptionStatus.streamingTranscription.rawValue == "streamingTranscription")
        #expect(Recording.TranscriptionStatus.queued.rawValue == "queued")
        #expect(Recording.TranscriptionStatus.transcribing.rawValue == "transcribing")
        #expect(Recording.TranscriptionStatus.completed.rawValue == "completed")
        #expect(Recording.TranscriptionStatus.failed.rawValue == "failed")
        #expect(Recording.TranscriptionStatus.cancelled.rawValue == "cancelled")
    }
    
    @Test("TranscriptionStatus Codable round-trip")
    func statusCodableRoundTrip() throws {
        let original = Recording.TranscriptionStatus.completed
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Recording.TranscriptionStatus.self, from: data)
        #expect(decoded == .completed)
    }
    
    @Test("TranscriptionStatus init from valid raw value")
    func statusInitFromRawValue() {
        #expect(Recording.TranscriptionStatus(rawValue: "pending") == .pending)
    }
    
    @Test("TranscriptionStatus init from invalid raw value is nil")
    func statusInvalidRawValue() {
        #expect(Recording.TranscriptionStatus(rawValue: "unknown") == nil)
    }
}
