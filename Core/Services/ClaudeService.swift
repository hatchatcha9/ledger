import Foundation
import UIKit

// MARK: - Proxy config
// Proxy URL and app secret are defined in Secrets.swift (gitignored).
// Copy Secrets.swift.example → Secrets.swift and fill in the values.
// ClaudeProxySecrets.proxyBaseURL  — Railway domain from: railway domain
// ClaudeProxySecrets.appSecret     — must match APP_SECRET on the Railway service

// MARK: - Service

final class ClaudeService {

    struct APIMessage: Codable {
        let role:    String
        let content: String
    }

    private struct RequestBody: Codable {
        let messages: [APIMessage]
        let system:   String
    }

    private struct ResponseBody: Codable {
        let content: String?
        let error:   String?
    }

    enum ServiceError: LocalizedError {
        case apiError(String)
        case emptyResponse
        var errorDescription: String? {
            switch self {
            case .apiError(let msg): return msg
            case .emptyResponse:     return "No response from Claude"
            }
        }
    }

    // A stable UUID stored on-device, sent as X-Device-Id for per-device rate limiting.
    private static var deviceID: String {
        let key = "ledger.deviceID"
        if let stored = UserDefaults.standard.string(forKey: key) { return stored }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }

    func send(messages: [APIMessage], system: String) async throws -> String {
        guard let url = URL(string: "\(ClaudeProxySecrets.proxyBaseURL)/chat") else {
            throw ServiceError.apiError("Proxy URL not configured — copy Secrets.swift.example → Secrets.swift")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",              forHTTPHeaderField: "Content-Type")
        req.setValue(ClaudeProxySecrets.appSecret,    forHTTPHeaderField: "x-app-secret")
        req.setValue(Self.deviceID,                   forHTTPHeaderField: "x-device-id")
        req.timeoutInterval = 30

        req.httpBody = try JSONEncoder().encode(RequestBody(messages: messages, system: system))

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = (try? JSONDecoder().decode(ResponseBody.self, from: data))?.error
                ?? "HTTP \(http.statusCode)"
            throw ServiceError.apiError(msg)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        if let err = decoded.error { throw ServiceError.apiError(err) }
        guard let text = decoded.content, !text.isEmpty else { throw ServiceError.emptyResponse }
        return text
    }
}
