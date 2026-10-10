import Foundation

// Fetches live market prices from Yahoo Finance.
// Crypto symbols get a "-USD" suffix (BTC → BTC-USD); everything else is passed as-is.
// Call refresh(assets:) from the Portfolio view — it's safe to call concurrently
// since @MainActor serialises all mutations to the published properties.
@MainActor
final class PriceService: ObservableObject {

    @Published private(set) var prices:      [String: Double] = [:]  // symbol → USD price
    @Published private(set) var changes:     [String: Double] = [:]  // symbol → 24 h % change
    @Published private(set) var isLoading    = false
    @Published private(set) var lastUpdated: Date?   = nil
    @Published private(set) var fetchError:  String? = nil

    // Full refresh — pass both owned assets and watchlist items so they all
    // fetch in one round-trip. Watchlist defaults to empty for callers that
    // don't have the entity in scope yet.
    func refresh(assets: [Asset], watchlist: [WatchlistItem] = []) async {
        let assetTickers     = assets.map   { yahooTicker($0.wrappedSymbol, kind: $0.assetKind) }
        let watchlistTickers = watchlist.map { yahooTicker($0.wrappedSymbol, kind: $0.assetKind) }

        // Deduplicate while preserving order.
        var seen = Set<String>()
        let tickers = (assetTickers + watchlistTickers).filter { seen.insert($0).inserted }
        guard !tickers.isEmpty, !isLoading else { return }   // Bug 3: guard concurrent calls

        isLoading  = true
        fetchError = nil

        var components = URLComponents(string: "https://query2.finance.yahoo.com/v7/finance/quote")!
        components.queryItems = [URLQueryItem(name: "symbols", value: tickers.joined(separator: ","))]
        guard let url = components.url else { isLoading = false; return }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response  = try JSONDecoder().decode(YFQuoteResponse.self, from: data)

            for quote in response.quoteResponse.result ?? [] {
                let sym        = symbolFromTicker(quote.symbol)
                prices[sym]  = quote.regularMarketPrice
                changes[sym] = quote.regularMarketChangePercent ?? 0
            }
            lastUpdated = .now
        } catch {
            fetchError = "Prices unavailable — check your connection."
        }

        isLoading = false
    }

    // MARK: - Ticker helpers

    private func yahooTicker(_ symbol: String, kind: AssetType) -> String {
        kind == .crypto ? "\(symbol)-USD" : symbol
    }

    private func symbolFromTicker(_ ticker: String) -> String {
        ticker.hasSuffix("-USD") ? String(ticker.dropLast(4)) : ticker
    }
}

// MARK: - Decodable response models

private struct YFQuoteResponse: Decodable {
    let quoteResponse: YFResult
}

private struct YFResult: Decodable {
    let result: [YFQuote]?   // Bug 7: Yahoo returns null on outages/bad symbols
}

private struct YFQuote: Decodable {
    let symbol:                     String
    let regularMarketPrice:         Double
    let regularMarketChangePercent: Double?  // absent when market hasn't opened yet
}
