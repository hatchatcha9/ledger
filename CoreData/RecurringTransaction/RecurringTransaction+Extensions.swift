import Foundation

extension RecurringTransaction {
    var wrappedName: String     { name     ?? "Unnamed" }
    var wrappedNotes: String    { notes    ?? "" }
    var wrappedCategory: String { category ?? "other" }
    var wrappedFrequency: String { frequency ?? "monthly" }

    var transactionCategory: TransactionCategory {
        TransactionCategory(rawValue: wrappedCategory) ?? .other
    }

    var recurringFrequency: RecurringFrequency {
        RecurringFrequency(rawValue: wrappedFrequency) ?? .monthly
    }

    var isExpense: Bool { amount < 0 }
}
