import Foundation

extension CDTransaction {

    var wrappedNotes: String { notes ?? "" }

    var transactionCategory: TransactionCategory {
        TransactionCategory(rawValue: category ?? "") ?? .other
    }

    // A transaction is an expense when its amount is negative.
    var isExpense: Bool { amount < 0 }

    // Absolute value for display; the sign is conveyed by color.
    var displayAmount: Double { abs(amount) }
}
