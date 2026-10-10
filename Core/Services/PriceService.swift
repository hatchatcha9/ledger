import Foundation

// Fetches live market prices from Yahoo Finance.
// Crypto symbols get a "-USD" suffix (BTC → BTC-USD); everything else is passed as-is.
// Call refresh(assets:) from the Portfolio view — it's safe to call concurrently
// since @MainActor serialises all mutations to the published properties.
@MainActor
final class PriceService: ObservableObject {

    @Published private(set) var prices:      [String: Double] = [:]  // symbol → price in native currency
    @Published private(set) var changes:     [String: Double] = [:]  // symbol → 24 h % change
    @Published private(set) var fxRates:     [String: Double] = [:]  // "EUR" → USD per 1 EUR
    @Published private(set) var isLoading    = false
    @Published private(set) var lastUpdated: Date?   = nil
    @Published private(set) var fetchError:  String? = nil

    // Converts an amount from `currency` to USD. Returns nil if rate unknown.
    func usdValue(of amount: Double, currency: String) -> Double {
        guard currency != "USD" else { return amount }
        guard let rate = fxRates[currency] else { return amount } // fallback: raw sum
        return amount * rate
    }

    // Full refresh — pass both owned assets and watchlist items so they all
    // fetch in one round-trip. Also pass account currencies to fetch FX rates.
    func refresh(assets: [Asset], watchlist: [WatchlistItem] = [], currencies: [String] = []) async {
        let assetTickers     = assets.map   { yahooTicker($0.wrappedSymbol, kind: $0.assetKind) }
        let watchlistTickers = watchlist.map { yahooTicker($0.wrappedSymbol, kind: $0.assetKind) }
        // FX tickers: "EURUSD=X", "JPYUSD=X", etc. (non-USD account currencies only)
        let fxTickers = currencies
            .filter { $0 != "USD" }
            .map    { "\($0)USD=X" }

        // Deduplicate while preserving order.
        var seen = Set<String>()
        let tickers = (assetTickers + watchlistTickers + fxTickers).filter { seen.insert($0).inserted }
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
                if quote.symbol.hasSuffix("USD=X") {
                    // FX ticker e.g. "EURUSD=X" → store rate under "EUR"
                    let currency = String(quote.symbol.dropLast(5))
                    fxRates[currency] = quote.regularMarketPrice
                } else {
                    let sym        = symbolFromTicker(quote.symbol)
                    prices[sym]  = quote.regularMarketPrice
                    changes[sym] = quote.regularMarketChangePercent ?? 0
                }
            }
            lastUpdated = .now
            // Cache prices and FX rates in the shared App Group so the widget
            // can show correct market values and convert multi-currency balances.
            if let shared = UserDefaults(suiteName: "group.ledger") {
                if let encoded = try? JSONEncoder().encode(prices) {
                    shared.set(encoded, forKey: "cachedPrices")
                }
                if let encoded = try? JSONEncoder().encode(fxRates) {
                    shared.set(encoded, forKey: "cachedFXRates")
                }
            }
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
