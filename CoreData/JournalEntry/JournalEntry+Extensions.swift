import Foundation

extension JournalEntry {

    var wrappedSymbol: String      { symbol      ?? "???" }
    var wrappedNotes: String       { notes       ?? "" }
    var wrappedStrategyTag: String { strategyTag ?? "" }

    var tradeOutcome: TradeOutcome {
        TradeOutcome(rawValue: outcome ?? "") ?? .open
    }

    var tradeDirection: TradeDirection {
        TradeDirection(rawValue: direction ?? "") ?? .long
    }

    var isOpen: Bool { tradeOutcome == .open }

    // Realised P&L — only meaningful when the trade is closed (exitPrice set).
    // For a long: (exit - entry) × size. Size is 1 unit here; in a richer model
    // you'd store quantity separately.
    var realisedPnL: Double? {
        guard !isOpen, exitPrice != 0 else { return nil }
        let multiplier: Double = tradeDirection == .long ? 1 : -1
        return multiplier * (exitPrice - entryPrice)
    }

    // Conviction displayed as filled stars.
    var convictionStars: String {
        let filled = Int(conviction)
        let empty  = 5 - filled
        return String(repeating: "★", count: max(0, filled)) +
               String(repeating: "☆", count: max(0, empty))
    }
}
