import Foundation
import WhisperKit

struct ParakeetHotword: Sendable {
    let text: String
    let weight: Float
}

struct InferenceBiasingEntry: Sendable {
    let text: String
    let weight: Float
}

/// A utility to compile user dictionary rules into model-specific structures for inference biasing.
struct DictionaryBiasingCompiler {
    
    /// Compiles replacement rules into an array of token IDs for WhisperKit.
    ///
    /// - Parameters:
    ///   - rules: The user's replacement rules.
    ///   - tokenizer: The tokenizer used by the WhisperKit instance.
    ///   - maxTokens: The maximum number of tokens allowed in the prompt window (typically 224 for Whisper).
    /// - Returns: An array of token IDs representing the biased prompt context.
    static func compileWhisperPromptTokens(from rules: [ReplacementRule], tokenizer: WhisperTokenizer?, maxTokens: Int = 224) -> [Int] {
        let entries = rules.map {
            InferenceBiasingEntry(text: $0.textToReplace, weight: $0.weight)
        }
        return compileWhisperPromptTokens(from: entries, tokenizer: tokenizer, maxTokens: maxTokens)
    }

    static func compileWhisperPromptTokens(from entries: [InferenceBiasingEntry], tokenizer: WhisperTokenizer?, maxTokens: Int = 224) -> [Int] {
        guard let tokenizer = tokenizer, !entries.isEmpty else { return [] }

        var promptTokens: [Int] = []

        for entry in entries {
            // WhisperKit often prefers words starting with a space to match mid-sentence tokens correctly
            let words = [" " + entry.text, entry.text]
            for word in words {
                let encoded = tokenizer.encode(text: word)
                if !encoded.isEmpty {
                    // We repeat the token sequence based on its weight to artificially "boost" it
                    let repeatCount = Int(max(1.0, entry.weight))
                    for _ in 0..<repeatCount {
                        promptTokens.append(contentsOf: encoded)
                    }
                }
            }
        }
        
        // Truncate to the maximum allowed context size
        if promptTokens.count > maxTokens {
            promptTokens = Array(promptTokens.suffix(maxTokens))
        }
        
        return promptTokens
    }
    
    /// Compiles replacement rules into a temporary hotwords text file required by Sherpa-ONNX (Parakeet).
    ///
    /// - Parameter rules: The user's replacement rules.
    /// - Returns: A tuple containing the file path of the compiled hotwords and the average calculated score.
    static func compileParakeetHotwordsFile(from hotwords: [ParakeetHotword]) -> (path: String, avgScore: Float)? {
        guard !hotwords.isEmpty else { return nil }
        
        let tempDir = FileManager.default.temporaryDirectory
        let hotwordsURL = tempDir.appendingPathComponent("parakeet_hotwords.txt")
        
        var lines: [String] = []
        var totalWeight: Float = 0
        var count: Float = 0
        
        for hotword in hotwords {
            let text = hotword.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                lines.append("\(text) \(hotword.weight)")
                totalWeight += hotword.weight
                count += 1
            }
        }
        
        guard !lines.isEmpty else { return nil }
        
        do {
            let content = lines.joined(separator: "\n")
            try content.write(to: hotwordsURL, atomically: true, encoding: .utf8)
            let avgScore = totalWeight / count
            return (path: hotwordsURL.path, avgScore: avgScore)
        } catch {
            print("Failed to write Parakeet hotwords file: \(error)")
            return nil
        }
    }
}
