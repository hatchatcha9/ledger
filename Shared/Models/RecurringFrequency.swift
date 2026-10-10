import Foundation

enum RecurringFrequency: String, CaseIterable, Identifiable {
    case weekly    = "weekly"
    case biweekly  = "biweekly"
    case monthly   = "monthly"
    case yearly    = "yearly"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly:   return "Weekly"
        case .biweekly: return "Every 2 Weeks"
        case .monthly:  return "Monthly"
        case .yearly:   return "Yearly"
        }
    }

    func nextDate(after date: Date) -> Date {
        let cal = Calendar.current
        switch self {
        case .weekly:   return cal.date(byAdding: .day,   value: 7,  to: date) ?? date
        case .biweekly: return cal.date(byAdding: .day,   value: 14, to: date) ?? date
        case .monthly:  return cal.date(byAdding: .month, value: 1,  to: date) ?? date
        case .yearly:   return cal.date(byAdding: .year,  value: 1,  to: date) ?? date
        }
    }
}
