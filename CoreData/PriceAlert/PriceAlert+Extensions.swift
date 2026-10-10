import Foundation

extension PriceAlert {
    var wrappedSymbol: String { symbol ?? "???" }
    var wrappedNote:   String { note   ?? "" }

    var alertCondition: PriceAlertCondition {
        PriceAlertCondition(rawValue: condition ?? "") ?? .above
    }

    func isTriggered(by currentPrice: Double) -> Bool {
        switch alertCondition {
        case .above: return currentPrice >= targetPrice
        case .below: return currentPrice <= targetPrice
        }
    }
}
