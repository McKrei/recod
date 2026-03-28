import Foundation

enum PostProcessingPromptDefaults {
    static let systemPrompt = "You are a text post-processor. Return only final transformed text."

    static let userPrompt = """
    Transcript:
    ${output}
    """
}
