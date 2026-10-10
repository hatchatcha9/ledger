import Foundation
import Combine
import UIKit

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages:    [ChatMessage] = []
    @Published var isLoading    = false
    @Published var errorMessage: String?

    // Injected by the presenting view before the sheet appears.
    var financialContext = ""

    private let service = ClaudeService()

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isLoading else { return }

        messages.append(ChatMessage(role: "user", text: trimmed))
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
            messages.removeLast()   // remove the user message that didn't go through
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

        == QUANT TRADING SYSTEM (BACKGROUND) ==
        The user runs a separate automated paper-trading system. Live status is included above in \
        the financial snapshot when available. Background context:
        - 5 bots on Alpaca paper account: 3 main (BTC/ETH/SOL) + 2 mini (BTC/ETH)
        - Strategy: 200-day trend filter (long when price > 200d MA, flat otherwise)
        - Emergency stop: 20% drawdown kills all positions
        - Fees: 24 bps actual vs 10 bps in backtest (fee drag is real)
        - Holdout: ETH 18d filter beat BnH (-35.8% vs +5.3%) but Sharpe 0.32 < 0.50 floor
        - No intraday strategy has survived holdout — daily bars only so far
        - 3 forward tests running; verdict ~March 2027
        - Status site: https://quant-system-live.netlify.app
        - Currently researching Hyperliquid day-trading (liquidation cascade momentum, vol breakout)
        When asked about trading strategy, the crypto bots, or whether to go live, draw on all of this.
        """
    }
}
