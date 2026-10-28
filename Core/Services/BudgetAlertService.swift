import UserNotifications
import CoreData

struct BudgetAlertService {

    // Call from DashboardView.onAppear (and whenever transactions change).
    // Fires a local notification the first time a budget crosses 80 % or 100 %
    // in the current calendar month; subsequent calls are no-ops because the
    // notification ID is month-scoped and we check pending requests first.
    static func checkAndNotify(budgets: [Budget], transactions: [CDTransaction]) {
        let cal       = Calendar.current
        let now       = Date()
        let year      = cal.component(.year,  from: now)
        let month     = cal.component(.month, from: now)
        let yearMonth = "\(year)-\(month)"

        for budget in budgets where budget.monthlyLimit > 0 {
            let spent = transactions
                .filter { tx in
                    guard tx.amount < 0,
                          tx.category == budget.category,
                          let d = tx.date else { return false }
                    return cal.component(.year,  from: d) == year
                        && cal.component(.month, from: d) == month
                }
                .reduce(0) { $0 + abs($1.amount) }

            let ratio   = spent / budget.monthlyLimit
            let catName = budget.transactionCategory.displayName

            if ratio >= 1.0 {
                schedule(
                    id:    "budget-over-\(budget.wrappedCategory)-\(yearMonth)",
                    title: "Budget Exceeded",
                    body:  "\(catName) spending has gone over your monthly budget."
                )
            } else if ratio >= 0.8 {
                schedule(
                    id:    "budget-warn-\(budget.wrappedCategory)-\(yearMonth)",
                    title: "Budget Alert: \(catName)",
                    body:  "\(catName) is at \(Int(ratio * 100))% of your monthly budget."
                )
            }
        }
    }

    private static func schedule(id: String, title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        // Only schedule if we don't already have this notification pending.
        center.getPendingNotificationRequests { pending in
            guard !pending.contains(where: { $0.identifier == id }) else { return }
            let content   = UNMutableNotificationContent()
            content.title = title
            content.body  = body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}
