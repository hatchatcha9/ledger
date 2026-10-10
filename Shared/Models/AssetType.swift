import Foundation

enum AssetType: String, CaseIterable, Identifiable {
    case crypto    = "crypto"
    case stock     = "stock"
    case etf       = "etf"
    case commodity = "commodity"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .crypto:    return "Cryptocurrency"
        case .stock:     return "Stock"
        case .etf:       return "ETF"
        case .commodity: return "Commodity"
        }
    }

    var icon: String {
        switch self {
        case .crypto:    return "bitcoinsign.circle"
        case .stock:     return "chart.line.uptrend.xyaxis"
        case .etf:       return "chart.bar.fill"
        case .commodity: return "bolt.horizontal"
        }
    }
}
