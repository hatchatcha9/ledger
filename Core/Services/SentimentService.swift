import SwiftUI

// MARK: - Models

struct SentimentData {
    let symbol:    String
    let score:     Double    // -1.0 (very bearish) to +1.0 (very bullish)
    let label:     SentimentLabel
    let mentions:  Int
    let updatedAt: Date
}

enum SentimentLabel: String {
    case bullish = "Bullish"
    case neutral = "Neutral"
    case bearish = "Bearish"

    var color: Color {
        switch self {
        case .bullish: return .ledgerPositive
        case .neutral: return Color(.secondaryLabel)
        case .bearish: return .ledgerNegative
        }
    }

    var icon: String {
        switch self {
        case .bullish: return "arrow.up.circle.fill"
        case .neutral: return "minus.circle.fill"
        case .bearish: return "arrow.down.circle.fill"
        }
    }
}

// MARK: - StockTwits response models

private struct STResponse: Decodable {
    let symbol:   STSymbol?
    let messages: [STMessage]?

    struct STSymbol: Decodable {
        let watchlistCount: Int?
        enum CodingKeys: String, CodingKey { case watchlistCount = "watchlist_count" }
    }

    struct STMessage: Decodable {
        let entities: STEntities?
        struct STEntities: Decodable {
            let sentiment: STSentiment?
            struct STSentiment: Decodable { let basic: String? }
        }
    }
}

// MARK: - Service

@MainActor
final class SentimentService: ObservableObject {
    @Published private(set) var sentiment:  [String: SentimentData] = [:]
    @Published private(set) var isFetching  = false
    @Published private(set) var lastError:  String?

    private var lastFetchedAt: [String: Date] = [:]
    private static let cacheTTL: TimeInterval = 600   // 10 minutes

    // Crypto tickers use the ".X" suffix on StockTwits
    private static let cryptoTickers: Set<String> = [
        "BTC","ETH","SOL","DOGE","ADA","AVAX","DOT","LINK","MATIC","XRP","LTC","BCH","ATOM","UNI"
    ]

    func fetch(symbols: [String]) async {
        let tickers = symbols.map { $0.uppercased() }
        let stale   = tickers.filter {
            guard let last = lastFetchedAt[$0] else { return true }
            return Date().timeIntervalSince(last) > Self.cacheTTL
        }
        guard !stale.isEmpty else { return }

        isFetching = true
        lastError  = nil

        for ticker in stale {
            if let data = await fetchStockTwits(ticker: ticker) {
                sentiment[ticker]      = data
                lastFetchedAt[ticker]  = Date()
            }
        }

        isFetching = false
    }

    // nonisolated so URLSession runs off the main actor (won't block UI)
    private nonisolated func fetchStockTwits(ticker: String) async -> SentimentData? {
        let stSymbol = Self.cryptoTickers.contains(ticker) ? "\(ticker).X" : ticker
        guard let url = URL(string: "https://api.stocktwits.com/api/2/streams/symbol/\(stSymbol).json")
        else { return nil }

        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }

            let decoded  = try JSONDecoder().decode(STResponse.self, from: data)
            let messages = decoded.messages ?? []
            let bullish  = messages.filter { $0.entities?.sentiment?.basic == "Bullish" }.count
            let bearish  = messages.filter { $0.entities?.sentiment?.basic == "Bearish" }.count
            let total    = bullish + bearish
            let score    = total > 0 ? Double(bullish - bearish) / Double(total) : 0.0
            let mentions = decoded.symbol?.watchlistCount ?? total
            let label: SentimentLabel = score > 0.1 ? .bullish : score < -0.1 ? .bearish : .neutral

            return SentimentData(
                symbol:    ticker,
                score:     score,
                label:     label,
                mentions:  mentions,
                updatedAt: .now
            )
        } catch { return nil }
    }
}
