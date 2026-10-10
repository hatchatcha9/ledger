import Foundation

extension WatchlistItem {
    var wrappedSymbol:  String  { symbol ?? "???" }
    var wrappedName:    String  { name   ?? "" }
    var wrappedThesis:  String  { thesis ?? "" }
    var targetPriceValue: Double { targetPrice }
    var hasTargetPrice: Bool    { targetPrice > 0 }
    var assetKind:      AssetType { AssetType(rawValue: assetType ?? "") ?? .stock }
}
