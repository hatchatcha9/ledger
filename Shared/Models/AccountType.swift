import Foundation

enum AccountType: String, CaseIterable, Identifiable {
    case checking    = "checking"
    case savings     = "savings"
    case creditCard  = "creditCard"
    case brokerage   = "brokerage"
    case cryptoWallet = "cryptoWallet"
    case loan        = "loan"
    case cash        = "cash"
    case other       = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .checking:     return "Checking"
        case .savings:      return "Savings"
        case .creditCard:   return "Credit Card"
        case .brokerage:    return "Investment / Brokerage"
        case .cryptoWallet: return "Crypto Wallet"
        case .loan:         return "Loan / Debt"
        case .cash:         return "Cash"
        case .other:        return "Other"
        }
    }

    var icon: String {
        switch self {
        case .checking:     return "building.columns"
        case .savings:      return "banknote"
        case .creditCard:   return "creditcard"
        case .brokerage:    return "chart.line.uptrend.xyaxis"
        case .cryptoWallet: return "bitcoinsign.circle"
        case .loan:         return "arrow.up.arrow.down.circle"
        case .cash:         return "dollarsign.circle"
        case .other:        return "tray"
        }
    }

    // Loan and credit card balances are naturally negative (you owe money).
    var isDebt: Bool { self == .loan || self == .creditCard }
}
