import Foundation

enum AccountType: String, CaseIterable, Identifiable {
    case cash         = "cash"
    case brokerage    = "brokerage"
    case cryptoWallet = "cryptoWallet"
    case savings      = "savings"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cash:         return "Cash"
        case .brokerage:    return "Brokerage"
        case .cryptoWallet: return "Crypto Wallet"
        case .savings:      return "Savings"
        }
    }

    var icon: String {
        switch self {
        case .cash:         return "banknote"
        case .brokerage:    return "chart.line.uptrend.xyaxis"
        case .cryptoWallet: return "bitcoinsign.circle"
        case .savings:      return "building.columns"
        }
    }
}
