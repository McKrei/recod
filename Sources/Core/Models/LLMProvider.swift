import Foundation

enum BuiltinProviderID: String, CaseIterable, Codable, Sendable {
    case openAI = "openai"
    case openRouter = "openrouter"
    case groq = "groq"
    case cerebras = "cerebras"
    case zAI = "zai"
    case custom = "custom"
}

struct LLMProvider: Codable, Identifiable, Sendable, Hashable {
    var id: String
    var displayName: String
    var baseURL: String
    var isCustom: Bool
    var defaultModels: [String]

    static let customDefaultBaseURL = "http://localhost:11434/v1"

    static let presets: [LLMProvider] = [
        LLMProvider(
            id: BuiltinProviderID.openAI.rawValue,
            displayName: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            isCustom: false,
            defaultModels: ["gpt-4o", "gpt-4o-mini", "o3-mini"]
        ),
        LLMProvider(
            id: BuiltinProviderID.openRouter.rawValue,
            displayName: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            isCustom: false,
            defaultModels: ["openai/gpt-4o", "anthropic/claude-3-5-sonnet", "google/gemini-2.0-flash"]
        ),
        LLMProvider(
            id: BuiltinProviderID.groq.rawValue,
            displayName: "Groq",
            baseURL: "https://api.groq.com/openai/v1",
            isCustom: false,
            defaultModels: ["llama-3.3-70b-versatile", "llama3-8b-8192"]
        ),
        LLMProvider(
            id: BuiltinProviderID.cerebras.rawValue,
            displayName: "Cerebras",
            baseURL: "https://api.cerebras.ai/v1",
            isCustom: false,
            defaultModels: ["llama-3.3-70b", "llama3.1-8b"]
        ),
        LLMProvider(
            id: BuiltinProviderID.zAI.rawValue,
            displayName: "Z.AI",
            baseURL: "https://api.z.ai/api/paas/v4",
            isCustom: false,
            defaultModels: ["glm-4.7", "glm-5"]
        )
    ]
}
