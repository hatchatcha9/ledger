import Foundation
import CoreData

struct RecurringService {

    // Called once on app launch. Generates a CDTransaction for every overdue
    // recurring rule and advances nextDueDate past today.
    static func generateDue(in context: NSManagedObjectContext) {
        let request = RecurringTransaction.fetchRequest()
        request.predicate = NSPredicate(
            format: "isActive == YES AND nextDueDate <= %@",
            Date() as NSDate
        )

        guard let due = try? context.fetch(request), !due.isEmpty else { return }

        let calendar = Calendar.current
        let today    = calendar.startOfDay(for: .now)

        for recurring in due {
            guard let account = recurring.account,
                  var nextDue = recurring.nextDueDate else { continue }

            // Catch up all missed occurrences in one pass.
            while calendar.startOfDay(for: nextDue) <= today {
                let tx       = CDTransaction(context: context)
                tx.id        = UUID()
                tx.amount    = recurring.amount
                tx.category  = recurring.wrappedCategory
                tx.type      = recurring.isExpense ? "expense" : "income"
                tx.date      = nextDue
                tx.notes     = recurring.wrappedName
                tx.createdAt = .now
                tx.account   = account
                account.balance += recurring.amount

                nextDue = recurring.recurringFrequency.nextDate(after: nextDue)
            }

            recurring.nextDueDate = nextDue
        }

        try? context.save()
    }
}
