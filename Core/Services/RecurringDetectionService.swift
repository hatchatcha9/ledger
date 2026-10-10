import Foundation

struct DetectedPattern: Identifiable {
    let id        = UUID()
    let name:      String
    let amount:    Double
    let frequency: RecurringFrequency
    let sampleTransactions: [CDTransaction]
}

enum RecurringDetectionService {

    // Minimum occurrences to consider a pattern real.
    private static let minOccurrences = 2

    static func detect(in transactions: [CDTransaction],
                       excluding existing: [RecurringTransaction]) -> [DetectedPattern] {
        let existingNames = Set(existing.map { normalize($0.wrappedName) })

        // Group by normalized name + rounded amount.
        var groups: [String: [CDTransaction]] = [:]
        for tx in transactions {
            let key = groupKey(tx)
            groups[key, default: []].append(tx)
        }

        var patterns: [DetectedPattern] = []

        for (_, txs) in groups {
            guard txs.count >= minOccurrences else { continue }

            let sorted = txs.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
            guard let freq = dominantFrequency(sorted) else { continue }

            let name = sorted.first.map { normalized($0) } ?? ""
            guard !existingNames.contains(normalize(name)) else { continue }

            let amount = sorted.map(\.amount).reduce(0, +) / Double(sorted.count)
            patterns.append(DetectedPattern(
                name:               name,
                amount:             amount,
                frequency:          freq,
                sampleTransactions: Array(sorted.prefix(3))
            ))
        }

        // Sort: most frequent first, then by amount magnitude.
        return patterns.sorted { abs($0.amount) > abs($1.amount) }
    }

    // MARK: - Helpers

    private static func groupKey(_ tx: CDTransaction) -> String {
        let name   = normalize(normalized(tx))
        let bucket = Int(abs(tx.amount) / 5) * 5  // bucket to nearest $5
        return "\(name)_\(bucket)"
    }

    // Strip amounts, punctuation and normalise whitespace.
    private static func normalize(_ s: String) -> String {
        var out = s.lowercased()
        // Remove digits and common suffixes like "*1234"
        out = out.replacingOccurrences(of: #"\*\d+"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\d"#,    with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: #"[^a-z ]"#, with: " ", options: .regularExpression)
        // Collapse whitespace
        out = out.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        return out
    }

    private static func normalized(_ tx: CDTransaction) -> String {
        tx.wrappedNotes.isEmpty ? tx.transactionCategory.displayName : tx.wrappedNotes
    }

    private static func dominantFrequency(_ sorted: [CDTransaction]) -> RecurringFrequency? {
        guard sorted.count >= 2 else { return nil }

        var intervals: [Double] = []
        for i in 1..<sorted.count {
            guard let a = sorted[i-1].date, let b = sorted[i].date else { continue }
            intervals.append(b.timeIntervalSince(a) / 86400)  // days
        }
        guard !intervals.isEmpty else { return nil }

        let avg = intervals.reduce(0, +) / Double(intervals.count)

        switch avg {
        case 5...10:   return .weekly
        case 11...20:  return .biweekly
        case 21...45:  return .monthly
        case 46...400: return .yearly
        default:       return nil
        }
    }
}
