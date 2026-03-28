import Foundation

actor LLMService {
    static let shared = LLMService()

    func complete(
        messages: [LLMMessage],
        providerID: String,
        modelID: String
    ) async throws -> LLMMessage {
        guard let provider = LLMProviderStore.provider(for: providerID) ?? LLMProvider.presets.first(where: { $0.id == providerID }) else {
            throw LLMServiceError.providerNotFound(providerID: providerID)
        }

        let apiKey = KeychainService.loadAPIKey(forProviderID: providerID)
        return try await complete(messages: messages, baseURL: provider.baseURL, modelID: modelID, apiKey: apiKey)
    }

    func postProcess(
        text: String,
        systemPrompt: String,
        providerID: String,
        modelID: String
    ) async throws -> String {
        let normalizedPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let userText = PostProcessingPromptDefaults.userPrompt
            .replacingOccurrences(of: "${output_with_timestamps}", with: text)
            .replacingOccurrences(of: "${output}", with: text)

        let finalSystemPrompt = normalizedPrompt.isEmpty
            ? PostProcessingPromptDefaults.systemPrompt
            : normalizedPrompt

        let message = try await complete(
            messages: [
                LLMMessage(role: .system, content: finalSystemPrompt),
                LLMMessage(role: .user, content: userText)
            ],
            providerID: providerID,
            modelID: modelID
        )
        return message.content
    }

    func fetchModels(baseURL: String, apiKey: String?) async throws -> [String] {
        guard let url = URL(string: normalizedBaseURL(baseURL) + "/models") else {
            throw LLMServiceError.invalidBaseURL
        }

        await FileLogger.shared.log("LLM fetchModels start: \(url.absoluteString)", level: .debug)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20

        if let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            await FileLogger.shared.log("LLM fetchModels failed HTTP \(httpResponse.statusCode) for \(url.absoluteString)", level: .error)
            throw LLMServiceError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        let models = decoded.data.map(\.id).sorted()
        await FileLogger.shared.log("LLM fetchModels success: \(models.count) models", level: .debug)
        return models
    }

    private func complete(
        messages: [LLMMessage],
        baseURL: String,
        modelID: String,
        apiKey: String?
    ) async throws -> LLMMessage {
        guard let url = URL(string: normalizedBaseURL(baseURL) + "/chat/completions") else {
            throw LLMServiceError.invalidBaseURL
        }

        let payload = ChatCompletionsRequest(
            model: modelID,
            messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) }
        )

        let encoder = JSONEncoder()
        let payloadData = try encoder.encode(payload)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = payloadData

        await FileLogger.shared.log("LLM complete start: url=\(url.absoluteString), model=\(modelID), messages=\(messages.count)", level: .debug)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            await FileLogger.shared.log(
                "LLM complete failed HTTP \(httpResponse.statusCode), body=\(responseBody)",
                level: .error
            )
            throw LLMServiceError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        guard let first = decoded.choices.first else {
            throw LLMServiceError.emptyChoices
        }

        await FileLogger.shared.log("LLM complete success: model=\(modelID)", level: .debug)
        return LLMMessage(role: .assistant, content: first.message.content)
    }

    private func normalizedBaseURL(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasSuffix("/") {
            return String(cleaned.dropLast())
        }
        return cleaned
    }
}

enum LLMServiceError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case httpError(statusCode: Int)
    case providerNotFound(providerID: String)
    case emptyChoices

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Invalid provider URL."
        case .invalidResponse:
            return "Server returned an invalid response."
        case let .httpError(statusCode):
            return "Server returned HTTP \(statusCode)."
        case let .providerNotFound(providerID):
            return "Provider not found: \(providerID)."
        case .emptyChoices:
            return "LLM returned empty choices."
        }
    }
}

private struct ChatCompletionsRequest: Codable {
    struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [ChatMessage]
}

private struct ChatCompletionsResponse: Codable {
    struct Choice: Codable {
        struct ChatMessage: Codable {
            let role: String
            let content: String
        }

        let message: ChatMessage
    }

    let choices: [Choice]
}

private struct ModelsResponse: Codable {
    let data: [ModelItem]
}

private struct ModelItem: Codable {
    let id: String
}
