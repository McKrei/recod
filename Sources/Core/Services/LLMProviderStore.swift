import Foundation

enum LLMProviderStore {
    private static let customProvidersKey = "llmCustomProviders"

    static func allProviders() -> [LLMProvider] {
        LLMProvider.presets + loadCustomProviders()
    }

    static func provider(for id: String) -> LLMProvider? {
        allProviders().first(where: { $0.id == id })
    }

    static func loadCustomProviders() -> [LLMProvider] {
        guard let data = UserDefaults.standard.data(forKey: customProvidersKey) else {
            return []
        }

        let decoder = JSONDecoder()
        return (try? decoder.decode([LLMProvider].self, from: data)) ?? []
    }

    @discardableResult
    static func mergeImportedCustomProviders(_ imported: [LLMProvider]) -> Int {
        guard !imported.isEmpty else { return 0 }

        var current = loadCustomProviders()
        var importedCount = 0

        for provider in imported where provider.isCustom {
            if let index = current.firstIndex(where: { $0.id == provider.id }) {
                current[index] = provider
            } else if !current.contains(where: {
                $0.displayName.caseInsensitiveCompare(provider.displayName) == .orderedSame
                    && $0.baseURL.caseInsensitiveCompare(provider.baseURL) == .orderedSame
            }) {
                current.append(provider)
                importedCount += 1
            }
        }

        saveCustomProviders(current)
        return importedCount
    }

    @discardableResult
    static func upsertCustomProvider(
        id: String?,
        displayName: String,
        baseURL: String
    ) -> LLMProvider {
        var providers = loadCustomProviders()
        let providerID = id ?? UUID().uuidString
        let cleanedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        let provider = LLMProvider(
            id: providerID,
            displayName: cleanedName.isEmpty ? "Custom" : cleanedName,
            baseURL: cleanedBaseURL.isEmpty ? LLMProvider.customDefaultBaseURL : cleanedBaseURL,
            isCustom: true,
            defaultModels: []
        )

        if let index = providers.firstIndex(where: { $0.id == providerID }) {
            providers[index] = provider
        } else {
            providers.append(provider)
        }

        saveCustomProviders(providers)
        return provider
    }

    private static func saveCustomProviders(_ providers: [LLMProvider]) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(providers) else { return }
        UserDefaults.standard.set(data, forKey: customProvidersKey)
    }
}
