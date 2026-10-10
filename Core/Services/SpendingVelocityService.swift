import Foundation
import UserNotifications

struct VelocityAlert: Identifiable {
    let id            = UUID()
    let category:     TransactionCategory
    let currentPace:  Double   // projected full-month amount at current rate
    let historicalAvg: Double  // 3-month avg monthly spend
    let ratio:        Double   // currentPace / historicalAvg
}

enum SpendingVelocityService {

    private static let ratioThreshold: Double = 1.5  // 50% over average = alert
    private static let minHistoricalMonths = 2        // need at least 2 months of history

    // Returns categories where the current month's pace exceeds the threshold.
    static func anomalies(from transactions: [CDTransaction]) -> [VelocityAlert] {
        let cal   = Calendar.current
        let now   = Date()
        let year  = cal.component(.year,  from: now)
        let month = cal.component(.month, from: now)
        let dayOfMonth = Double(cal.component(.day, from: now))
        let daysInMonth = Double(cal.range(of: .day, in: .month, for: now)?.count ?? 30)

        guard dayOfMonth >= 5, daysInMonth > 0 else { return [] }  // not enough data yet

        let expenses = transactions.filter { $0.amount < 0 }

        var alerts: [VelocityAlert] = []

        for category in TransactionCategory.allCases where !category.isIncome {
            let catTx = expenses.filter { $0.transactionCategory == category }

            // Current month spend so far
            let thisMonthSpend = catTx.filter { tx in
                guard let d = tx.date else { return false }
                return cal.component(.year,  from: d) == year &&
                       cal.component(.month, from: d) == month
            }.reduce(0) { $0 + abs($1.amount) }

            guard thisMonthSpend > 0 else { continue }

            // Projected full-month pace
            let pace = (thisMonthSpend / dayOfMonth) * daysInMonth

            // Historical 3-month average (exclude current month)
            var monthlySums: [Double] = []
            for offset in 1...3 {
                guard let pastDate = cal.date(byAdding: .month, value: -offset, to: now) else { continue }
                let py = cal.component(.year,  from: pastDate)
                let pm = cal.component(.month, from: pastDate)
                let sum = catTx.filter { tx in
                    guard let d = tx.date else { return false }
                    return cal.component(.year,  from: d) == py &&
                           cal.component(.month, from: d) == pm
                }.reduce(0) { $0 + abs($1.amount) }
                if sum > 0 { monthlySums.append(sum) }
            }

            guard monthlySums.count >= minHistoricalMonths else { continue }

            let avg = monthlySums.reduce(0, +) / Double(monthlySums.count)
            guard avg > 0 else { continue }

            let ratio = pace / avg
            if ratio >= ratioThreshold {
                alerts.append(VelocityAlert(
                    category:      category,
                    currentPace:   pace,
                    historicalAvg: avg,
                    ratio:         ratio
                ))
            }
        }

        return alerts.sorted { $0.ratio > $1.ratio }
    }

    // Fire a local notification for each anomaly (throttled to once per category per day).
    static func fireNotifications(for alerts: [VelocityAlert]) {
        guard !alerts.isEmpty else { return }
        let center    = UNUserNotificationCenter.current()
        let defaults  = UserDefaults.standard
        let todayKey  = "velocityAlertDate"
        let today     = Calendar.current.startOfDay(for: .now)

        // Only fire once per day total to avoid spam.
        if let last = defaults.object(forKey: todayKey) as? Date,
           Calendar.current.isDate(last, inSameDayAs: today) { return }

        defaults.set(today, forKey: todayKey)

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            for alert in alerts.prefix(2) {  // max 2 at once
                let content       = UNMutableNotificationContent()
                content.title     = "Spending Alert — \(alert.category.displayName)"
                let pct           = Int((alert.ratio - 1) * 100)
                content.body      = "You're on pace to spend \(pct)% more than usual on \(alert.category.displayName.lowercased()) this month."
                content.sound     = .default

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                let id      = "velocity.\(alert.category.rawValue)"
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                center.add(request)
            }
        }
    }
}
