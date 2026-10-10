import Foundation

extension WatchlistItem {
    var wrappedSymbol: String { symbol ?? "???" }
    var wrappedName:   String { name   ?? "" }
    var assetKind:     AssetType { AssetType(rawValue: assetType ?? "") ?? .stock }
}
