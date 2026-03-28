import Foundation
import Testing
@testable import Recod

@Suite("PostProcessingPromptBuilder")
struct PostProcessingPromptBuilderTests {
    @Test("Blank prompt falls back to default template")
    func blankPromptFallsBackToDefaultTemplate() {
        let prompt = PostProcessingPromptBuilder.buildUserPrompt(
            prompt: "   \n",
            sourceText: "Hello world",
            timestampedText: nil
        )

        #expect(prompt == "Transcript:\nHello world")
    }

    @Test("Both placeholders are replaced from shared contract")
    func placeholdersAreReplaced() {
        let prompt = PostProcessingPromptBuilder.buildUserPrompt(
            prompt: "Raw: ${output}\nTimed: ${output_with_timestamps}",
            sourceText: "Hello world",
            timestampedText: "[0:00] Hello world"
        )

        #expect(prompt == "Raw: Hello world\nTimed: [0:00] Hello world")
    }

    @Test("Timestamp formatting falls back when segments are empty")
    func timestampFallbackUsesSourceText() {
        let formatted = PostProcessingPromptBuilder.formatOutputWithTimestamps(
            segments: [],
            fallbackText: "Fallback text"
        )

        #expect(formatted == "Fallback text")
    }

    @Test("Timestamp formatting skips empty segments and keeps fallback when needed")
    func timestampFormattingSkipsEmptySegments() {
        let fallback = PostProcessingPromptBuilder.formatOutputWithTimestamps(
            segments: [
                TranscriptionSegment(start: 0, end: 1, text: "   "),
                TranscriptionSegment(start: 3, end: 4, text: "Second line")
            ],
            fallbackText: "Fallback text"
        )

        #expect(fallback == "[0:03] Second line")
    }

    @Test("Resolved save path picks directory or file based on mode")
    func resolvedSavePathUsesSelectedMode() {
        let newFilePath = AddActionViewModel.resolvedSavePath(
            mode: .newFile,
            directoryPath: " /tmp/out ",
            existingFilePath: "/tmp/existing.txt"
        )
        let existingFilePath = AddActionViewModel.resolvedSavePath(
            mode: .existingFile,
            directoryPath: "/tmp/out",
            existingFilePath: " /tmp/existing.txt "
        )

        #expect(newFilePath == "/tmp/out")
        #expect(existingFilePath == "/tmp/existing.txt")
    }
}
