import Foundation

struct AIService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func generateDescription(appName: String, bundleID: String, apiKey: String) async throws -> String {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = "Write a brief 1-2 sentence description of the macOS app \"\(appName)\" (bundle ID: \(bundleID)). Focus on what it does. Be concise and factual. Output only the description, no quotes or preamble."

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 150,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "AIService", code: 0, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = (json["content"] as? [[String: Any]])?.first,
            let text = content["text"] as? String
        else {
            throw NSError(domain: "AIService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
