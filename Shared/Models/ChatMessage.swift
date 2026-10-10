import Foundation

struct ChatMessage: Identifiable {
    let id   = UUID()
    let role: String   // "user" | "assistant"
    let text: String
    var isUser: Bool { role == "user" }
}
