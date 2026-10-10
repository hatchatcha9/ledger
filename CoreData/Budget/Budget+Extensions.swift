import Foundation

extension Budget {
    var wrappedCategory: String { category ?? "other" }

    var transactionCategory: TransactionCategory {
        TransactionCategory(rawValue: wrappedCategory) ?? .other
    }
}
