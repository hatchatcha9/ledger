import Foundation

enum PriceAlertCondition: String, CaseIterable, Identifiable {
    case above = "above"
    case below = "below"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .above: return "Rises Above"
        case .below: return "Falls Below"
        }
    }

    var icon: String {
        switch self {
        case .above: return "arrow.up.circle"
        case .below: return "arrow.down.circle"
        }
    }
}
