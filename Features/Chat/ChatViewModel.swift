import Foundation
import Combine
import UIKit

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages:    [ChatMessage] = []
    @Published var isLoading    = false
    @Published var errorMessage: String?
    @Published private(set) var messagesUsedToday: Int = 0

    static let dailyLimit = 20

    var messagesRemainingToday: Int { max(0, Self.dailyLimit - messagesUsedToday) }

    // Injected by the presenting view before the sheet appears.
    var financialContext = ""

    private let service = ClaudeService()
    private let defaults = UserDefaults.standard

    init() {
        refreshDailyCount()
    }

    private func refreshDailyCount() {
        let today = todayKey()
        if defaults.string(forKey: "claudeMsgDate") == today {
            messagesUsedToday = defaults.integer(forKey: "claudeMsgCount")
        } else {
            // New day — reset
            defaults.set(today, forKey: "claudeMsgDate")
            defaults.set(0,     forKey: "claudeMsgCount")
            messagesUsedToday = 0
        }
    }

    private func incrementDailyCount() {
        refreshDailyCount()
        messagesUsedToday += 1
        defaults.set(messagesUsedToday, forKey: "claudeMsgCount")
    }

    private func todayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isLoading else { return }

        // If the previous send failed, a dangling user message sits at the end.
        // Replace it with the new message so the history stays valid (no two
        // consecutive user turns).
        if messages.last?.role == "user" {
            messages.removeLast()
        }

        messages.append(ChatMessage(role: "user", text: trimmed))
        incrementDailyCount()
        isLoading    = true
        errorMessage = nil

        // Build the message history for the API (all messages so far).
        let apiMessages = messages.map {
            ClaudeService.APIMessage(role: $0.role, content: $0.text)
        }

        do {
            let reply = try await service.send(
                messages: apiMessages,
                system:   systemPrompt
            )
            messages.append(ChatMessage(role: "assistant", text: reply))
        } catch {
            // Leave the user message in the list so they can see what failed.
            // It will be replaced when they retry.
            errorMessage = error.localizedDescription
            HapticService.error()
        }

        isLoading = false
    }

    func clearHistory() {
        messages.removeAll()
    }

    // MARK: - System prompt

    private var systemPrompt: String {
        """
        You are a personal finance and trading assistant built into the Ledger app on the user's iPhone. \
        You help with budgeting, portfolio analysis, trade strategy, and financial decisions. \
        Be concise and specific — lead with numbers when relevant. \
        Do not add disclaimers unless genuinely needed for a high-stakes decision.

        == USER'S CURRENT FINANCIAL SNAPSHOT ==
        \(financialContext.isEmpty ? "(No financial data loaded yet.)" : financialContext)
        """
    }
}
