import Foundation

enum AIProviderID: String, CaseIterable, Identifiable {
    case anthropic
    case openAICompatible = "openai_compatible"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openAICompatible: return "OpenAI-compatible (OpenAI, OpenRouter, Ollama, LM Studio…)"
        }
    }

    var keychainKey: String {
        switch self {
        case .anthropic: return "anthropic-api-key"
        case .openAICompatible: return "openai-compatible-api-key"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com"
        case .openAICompatible: return "https://api.openai.com/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-haiku-4-5-20251001"
        case .openAICompatible: return "gpt-4o-mini"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .anthropic: return true
        case .openAICompatible: return false // local servers like Ollama may not need one
        }
    }

    var supportsModelListFetch: Bool {
        switch self {
        case .anthropic: return true
        case .openAICompatible: return true
        }
    }
}

enum AIProviderSettings {
    static let selectedProviderKey = "selectedAIProvider"
    static let hasChosenProviderKey = "hasChosenAIProvider"
    static let modelKeyPrefix = "aiModel."
    static let baseURLKeyPrefix = "aiBaseURL."

    static var selectedProvider: AIProviderID {
        let raw = UserDefaults.standard.string(forKey: selectedProviderKey) ?? AIProviderID.anthropic.rawValue
        return AIProviderID(rawValue: raw) ?? .anthropic
    }

    static func setSelectedProvider(_ id: AIProviderID) {
        UserDefaults.standard.set(id.rawValue, forKey: selectedProviderKey)
    }

    static var hasChosenProvider: Bool {
        get { UserDefaults.standard.bool(forKey: hasChosenProviderKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasChosenProviderKey) }
    }

    static func model(for provider: AIProviderID) -> String {
        UserDefaults.standard.string(forKey: modelKeyPrefix + provider.rawValue) ?? provider.defaultModel
    }

    static func setModel(_ model: String, for provider: AIProviderID) {
        UserDefaults.standard.set(model, forKey: modelKeyPrefix + provider.rawValue)
    }

    static func baseURL(for provider: AIProviderID) -> String {
        UserDefaults.standard.string(forKey: baseURLKeyPrefix + provider.rawValue) ?? provider.defaultBaseURL
    }

    static func setBaseURL(_ url: String, for provider: AIProviderID) {
        UserDefaults.standard.set(url, forKey: baseURLKeyPrefix + provider.rawValue)
    }

    static func apiKey(for provider: AIProviderID) -> String? {
        KeychainHelper.load(for: provider.keychainKey)
    }
}

enum AIServiceError: LocalizedError {
    case missingAPIKey
    case http(Int, String)
    case decoding(String)
    case invalidConfig(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "No API key set. Add one in Settings."
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .decoding(let msg): return "Unexpected response: \(msg)"
        case .invalidConfig(let msg): return msg
        }
    }
}

struct AIService {
    /// Generate a description using whichever provider is currently selected.
    func generateDescription(appName: String, bundleID: String) async throws -> String {
        let provider = AIProviderSettings.selectedProvider
        let prompt = "Write a brief 1-2 sentence description of the macOS app \"\(appName)\" (bundle ID: \(bundleID)). Focus on what it does. Be concise and factual. Output only the description, no quotes or preamble."
        switch provider {
        case .anthropic:
            return try await callAnthropic(prompt: prompt)
        case .openAICompatible:
            return try await callOpenAICompatible(prompt: prompt)
        }
    }

    // MARK: Model listing

    static func fetchModels(for provider: AIProviderID) async throws -> [String] {
        switch provider {
        case .anthropic:
            return try await fetchAnthropicModels()
        case .openAICompatible:
            return try await fetchOpenAICompatibleModels()
        }
    }

    // MARK: Anthropic

    private func callAnthropic(prompt: String) async throws -> String {
        guard let apiKey = AIProviderSettings.apiKey(for: .anthropic), !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        let base = AIProviderSettings.baseURL(for: .anthropic)
        let model = AIProviderSettings.model(for: .anthropic)
        guard let url = URL(string: base + "/v1/messages") else {
            throw AIServiceError.invalidConfig("Invalid Anthropic base URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 150,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIServiceError.http((response as? HTTPURLResponse)?.statusCode ?? 0,
                                      String(data: data, encoding: .utf8) ?? "")
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = (json["content"] as? [[String: Any]])?.first,
            let text = content["text"] as? String
        else {
            throw AIServiceError.decoding("Anthropic response missing text")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fetchAnthropicModels() async throws -> [String] {
        guard let apiKey = AIProviderSettings.apiKey(for: .anthropic), !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        let base = AIProviderSettings.baseURL(for: .anthropic)
        guard let url = URL(string: base + "/v1/models") else {
            throw AIServiceError.invalidConfig("Invalid Anthropic base URL")
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIServiceError.http((response as? HTTPURLResponse)?.statusCode ?? 0,
                                      String(data: data, encoding: .utf8) ?? "")
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let models = json["data"] as? [[String: Any]]
        else {
            throw AIServiceError.decoding("Anthropic /v1/models response malformed")
        }
        return models.compactMap { $0["id"] as? String }.sorted()
    }

    // MARK: OpenAI-compatible

    private func callOpenAICompatible(prompt: String) async throws -> String {
        let base = AIProviderSettings.baseURL(for: .openAICompatible)
        let model = AIProviderSettings.model(for: .openAICompatible)
        guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else {
            throw AIServiceError.invalidConfig("Invalid base URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = AIProviderSettings.apiKey(for: .openAICompatible), !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 150,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIServiceError.http((response as? HTTPURLResponse)?.statusCode ?? 0,
                                      String(data: data, encoding: .utf8) ?? "")
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choice = (json["choices"] as? [[String: Any]])?.first,
            let message = choice["message"] as? [String: Any],
            let text = message["content"] as? String
        else {
            throw AIServiceError.decoding("OpenAI-compatible response missing message.content")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fetchOpenAICompatibleModels() async throws -> [String] {
        let base = AIProviderSettings.baseURL(for: .openAICompatible)
        guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/models") else {
            throw AIServiceError.invalidConfig("Invalid base URL")
        }
        var request = URLRequest(url: url)
        if let apiKey = AIProviderSettings.apiKey(for: .openAICompatible), !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIServiceError.http((response as? HTTPURLResponse)?.statusCode ?? 0,
                                      String(data: data, encoding: .utf8) ?? "")
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let models = json["data"] as? [[String: Any]]
        else {
            throw AIServiceError.decoding("/models response malformed")
        }
        return models.compactMap { $0["id"] as? String }.sorted()
    }
}
