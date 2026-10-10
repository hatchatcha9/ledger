import Foundation

// MARK: - API config
// The API key is never stored in source code. Users enter their own key in
// Settings → Ask Claude → API Key. It is stored only in UserDefaults (on-device).
enum ClaudeAPIConfig {
    static var apiKey: String {
        UserDefaults.standard.string(forKey: "anthropicAPIKey") ?? ""
    }
    static let model = "claude-sonnet-4-6"
}

// MARK: - Service

final class ClaudeService {

    struct APIMessage: Codable {
        let role:    String
        let content: String
    }

    private struct RequestBody: Codable {
        let model:      String
        let max_tokens: Int
        let system:     String
        let messages:   [APIMessage]
    }

    private struct ResponseBody: Codable {
        struct Content: Codable {
            let type: String
            let text: String?
        }
        let content: [Content]

        struct ErrorBody: Codable {
            let type:    String
            let message: String
        }
        let error: ErrorBody?
    }

    enum ServiceError: LocalizedError {
        case missingAPIKey
        case apiError(String)
        case emptyResponse
        var errorDescription: String? {
            switch self {
            case .missingAPIKey:      return "No API key set. Add your Anthropic key in Settings → Ask Claude."
            case .apiError(let msg):  return "API error: \(msg)"
            case .emptyResponse:      return "No response from Claude"
            }
        }
    }

    func send(messages: [APIMessage], system: String) async throws -> String {
        let key = ClaudeAPIConfig.apiKey
        guard !key.isEmpty else { throw ServiceError.missingAPIKey }

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw ServiceError.apiError("Invalid URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key,                forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")

        let body = RequestBody(
            model:      ClaudeAPIConfig.model,
            max_tokens: 1024,
            system:     system,
            messages:   messages
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = (try? JSONDecoder().decode(ResponseBody.self, from: data))?.error?.message
                ?? "HTTP \(http.statusCode)"
            throw ServiceError.apiError(msg)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        if let err = decoded.error { throw ServiceError.apiError(err.message) }
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text else {
            throw ServiceError.emptyResponse
        }
        return text
    }
}
