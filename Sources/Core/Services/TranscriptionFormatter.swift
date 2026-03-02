import Foundation

/// Shared utility for cleaning and formatting transcription output.
/// Removes WhisperKit special tokens and applies standard text normalization.
public enum TranscriptionFormatter {
    
    /// Removes WhisperKit special tokens (e.g. <|startoftranscript|>, <|en|>, etc.).
    /// Uses a regular expression to match anything within <| and |>.
    public static func cleanSpecialTokens(_ text: String) -> String {
        let pattern = "<\\|.*?\\|>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let range = NSRange(text.startIndex..., in: text)
        let cleaned = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
