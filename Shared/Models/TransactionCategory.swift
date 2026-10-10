import Foundation

enum TransactionCategory: String, CaseIterable, Identifiable {
    // Expenses
    case food          = "food"
    case transport     = "transport"
    case entertainment = "entertainment"
    case housing       = "housing"
    case utilities     = "utilities"
    case health        = "health"
    case shopping      = "shopping"
    // Income
    case salary        = "salary"
    case dividends     = "dividends"
    case tradeFee      = "tradeFee"   // negative expense (cost of trading)
    case other         = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .food:          return "Food & Drink"
        case .transport:     return "Transport"
        case .entertainment: return "Entertainment"
        case .housing:       return "Housing"
        case .utilities:     return "Utilities"
        case .health:        return "Health"
        case .shopping:      return "Shopping"
        case .salary:        return "Salary"
        case .dividends:     return "Dividends"
        case .tradeFee:      return "Trade Fee"
        case .other:         return "Other"
        }
    }

    var icon: String {
        switch self {
        case .food:          return "fork.knife"
        case .transport:     return "car"
        case .entertainment: return "popcorn"
        case .housing:       return "house"
        case .utilities:     return "bolt"
        case .health:        return "heart"
        case .shopping:      return "bag"
        case .salary:        return "dollarsign.circle"
        case .dividends:     return "chart.bar"
        case .tradeFee:      return "arrow.left.arrow.right.circle"
        case .other:         return "ellipsis.circle"
        }
    }

    // Expenses reduce balance; income/dividends/salary increase it.
    var isIncome: Bool {
        switch self {
        case .salary, .dividends: return true
        default: return false
        }
    }

    static var expenseCategories: [TransactionCategory] {
        allCases.filter { !$0.isIncome && $0 != .tradeFee }
    }
}
