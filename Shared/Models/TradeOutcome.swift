import SwiftUI

enum TradeOutcome: String, CaseIterable, Identifiable {
    case open       = "open"
    case win        = "win"
    case loss       = "loss"
    case breakeven  = "breakeven"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .open:      return "Open"
        case .win:       return "Win"
        case .loss:      return "Loss"
        case .breakeven: return "Break-even"
        }
    }

    var color: Color {
        switch self {
        case .open:      return Color(.secondaryLabel)
        case .win:       return .ledgerPositive
        case .loss:      return .ledgerNegative
        case .breakeven: return .orange
        }
    }

    var icon: String {
        switch self {
        case .open:      return "clock"
        case .win:       return "arrow.up.right"
        case .loss:      return "arrow.down.right"
        case .breakeven: return "equal"
        }
    }
}

enum TradeDirection: String, CaseIterable, Identifiable {
    case long  = "long"
    case short = "short"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .long:  return "Long"
        case .short: return "Short"
        }
    }
}
