import Foundation

// MARK: - API key
// Replace the value below with your Anthropic API key before shipping.
// Never commit a real key to source control.
enum ClaudeAPIConfig {
    static let apiKey = "REDACTED"
    static let model  = "claude-sonnet-4-6"
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
        case apiError(String)
        case emptyResponse
        var errorDescription: String? {
            switch self {
            case .apiError(let msg):  return "API error: \(msg)"
            case .emptyResponse:      return "No response from Claude"
            }
        }
    }

    func send(messages: [APIMessage], system: String) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw ServiceError.apiError("Invalid URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",         forHTTPHeaderField: "Content-Type")
        req.setValue(ClaudeAPIConfig.apiKey,      forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",               forHTTPHeaderField: "anthropic-version")

        let body = RequestBody(
            model:      ClaudeAPIConfig.model,
            max_tokens: 1024,
            system:     system,
            messages:   messages
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            // Try to extract Anthropic's error message; fall back to the status code.
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
