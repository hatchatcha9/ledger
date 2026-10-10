import Foundation

extension Account {

    // MARK: - Safe unwrappers
    // Core Data optionals exist because the object may not yet have been saved.
    // These give a sensible default so views never have to deal with nil.
    var wrappedName: String     { name     ?? "Unnamed Account" }
    var wrappedCurrency: String { currency ?? "USD" }

    // MARK: - Typed enum
    var accountType: AccountType {
        AccountType(rawValue: type ?? "") ?? .cash
    }

    // MARK: - Sorted child arrays
    // NSSet has no guaranteed order; sorting here means every caller gets the same order.
    var transactionsArray: [CDTransaction] {
        (transactions as? Set<CDTransaction> ?? [])
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var assetsArray: [Asset] {
        (assets as? Set<Asset> ?? [])
            .sorted { $0.wrappedSymbol < $1.wrappedSymbol }
    }

    var recurringTransactionsArray: [RecurringTransaction] {
        (recurringTransactions as? Set<RecurringTransaction> ?? [])
            .filter { $0.isActive }
            .sorted { ($0.nextDueDate ?? .distantFuture) < ($1.nextDueDate ?? .distantFuture) }
    }

    // MARK: - Computed balance helpers
    // Used by the Dashboard to show today's activity without a separate fetch.
    var todaysTransactions: [CDTransaction] {
        let calendar = Calendar.current
        return transactionsArray.filter {
            guard let date = $0.date else { return false }
            return calendar.isDateInToday(date)
        }
    }
}
