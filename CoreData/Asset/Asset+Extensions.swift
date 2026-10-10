import Foundation

extension Asset {

    var wrappedSymbol: String { symbol ?? "???" }
    var wrappedName: String   { name   ?? "Unknown Asset" }

    var assetKind: AssetType {
        AssetType(rawValue: assetType ?? "") ?? .crypto
    }

    // Cost basis = average cost × quantity. Used to compute unrealised P&L
    // once we have a live price from PriceService (Day 3).
    var costBasis: Double { avgCost * quantity }

    // P&L relative to a given current price.
    func unrealisedPnL(currentPrice: Double) -> Double {
        (currentPrice - avgCost) * quantity
    }

    func unrealisedPnLPercent(currentPrice: Double) -> Double {
        guard avgCost != 0 else { return 0 }
        return ((currentPrice - avgCost) / avgCost) * 100
    }
}
