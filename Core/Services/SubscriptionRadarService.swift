import Foundation

struct DetectedSubscription: Identifiable {
    let id          = UUID()
    let name:        String
    let avgAmount:   Double
    let annualCost:  Double
    let frequency:   String
    let lastCharged: Date
    let priceChange: Double?   // positive = price went up
    let occurrences: Int
}

struct SubscriptionRadarService {

    // Scans past transactions for recurring charges and returns them sorted by
    // annual cost descending.
    static func detect(from transactions: [CDTransaction]) -> [DetectedSubscription] {
        let expenses = transactions.filter { $0.amount < 0 && $0.wrappedNotes.count >= 3 }

        // Group by normalised note string.
        var groups: [String: [CDTransaction]] = [:]
        for tx in expenses {
            let key = normalise(tx.wrappedNotes)
            guard !key.isEmpty else { continue }
            groups[key, default: []].append(tx)
        }

        var results: [DetectedSubscription] = []

        for (key, txs) in groups {
            guard txs.count >= 2 else { continue }
            let sorted = txs.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }

            // Calculate average interval between consecutive charges.
            var intervals: [Double] = []
            for i in 1 ..< sorted.count {
                guard let d0 = sorted[i-1].date, let d1 = sorted[i].date else { continue }
                intervals.append(d1.timeIntervalSince(d0) / 86_400)
            }
            guard !intervals.isEmpty else { continue }
            let avgInterval = intervals.reduce(0, +) / Double(intervals.count)

            let (frequency, multiplier): (String, Double)
            switch avgInterval {
            case 6 ..< 9:     (frequency, multiplier) = ("Weekly",    52)
            case 12 ..< 17:   (frequency, multiplier) = ("Biweekly",  26)
            case 25 ..< 36:   (frequency, multiplier) = ("Monthly",   12)
            case 85 ..< 100:  (frequency, multiplier) = ("Quarterly",  4)
            case 340 ..< 400: (frequency, multiplier) = ("Annual",     1)
            default: continue
            }

            let amounts    = sorted.map { abs($0.amount) }
            let avgAmount  = amounts.reduce(0, +) / Double(amounts.count)
            let priceChange: Double? = {
                guard amounts.count >= 2 else { return nil }
                let diff = amounts.last! - amounts.first!
                return abs(diff) >= 0.50 ? diff : nil
            }()

            results.append(DetectedSubscription(
                name:        key,
                avgAmount:   avgAmount,
                annualCost:  avgAmount * multiplier,
                frequency:   frequency,
                lastCharged: sorted.last?.date ?? .now,
                priceChange: priceChange,
                occurrences: txs.count
            ))
        }

        return results.sorted { $0.annualCost > $1.annualCost }
    }

    // Strip trailing digits/year, currency symbols, and whitespace; title-case.
    private static func normalise(_ raw: String) -> String {
        var s = raw.lowercased()
        // Remove common suffixes: "2024", "- jan", "$15.99", "#123"
        s = s.replacingOccurrences(of: "\\s*\\d{4}\\s*$", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s*-\\s*\\w+\\s*$", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "[\\$£€#*]", with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep first four words to group "Netflix 4K" with "Netflix"
        let words = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.prefix(4)
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
