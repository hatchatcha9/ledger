import Foundation

// MARK: - Split item model (stored as JSON in splitsJSON)
struct TransactionSplit: Codable, Identifiable {
    var id       = UUID()
    var amount:   Double
    var category: String

    var transactionCategory: TransactionCategory {
        TransactionCategory(rawValue: category) ?? .other
    }
}

extension CDTransaction {

    var wrappedNotes: String { notes ?? "" }

    var transactionCategory: TransactionCategory {
        TransactionCategory(rawValue: category ?? "") ?? .other
    }

    var isExpense: Bool { amount < 0 }
    var displayAmount: Double { abs(amount) }

    // MARK: - Split support

    var splits: [TransactionSplit] {
        get {
            guard let json = splitsJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([TransactionSplit].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            if newValue.isEmpty {
                splitsJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let str = String(data: data, encoding: .utf8) {
                splitsJSON = str
            }
        }
    }

    var isSplit: Bool { splitsJSON != nil && !splits.isEmpty }
}
