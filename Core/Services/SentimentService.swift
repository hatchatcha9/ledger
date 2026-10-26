import SwiftUI

// MARK: - Models

struct SentimentData {
    let symbol:        String
    let score:         Double       // -1.0 (very bearish) to +1.0 (very bullish)
    let label:         SentimentLabel
    let mentions:      Int
    let topMessages:   [String]     // up to 10 recent post bodies
    var claudeInsight: String?      // nil until Claude has analyzed them
    let updatedAt:     Date
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
        let body:     String?
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
    @Published private(set) var sentiment:   [String: SentimentData] = [:]
    @Published private(set) var isFetching   = false
    @Published private(set) var isAnalyzing: [String: Bool] = [:]
    @Published private(set) var lastError:   String?

    private var lastFetchedAt: [String: Date] = [:]
    private static let cacheTTL: TimeInterval = 600

    private static let cryptoTickers: Set<String> = [
        "BTC","ETH","SOL","DOGE","ADA","AVAX","DOT","LINK","MATIC","XRP","LTC","BCH","ATOM","UNI"
    ]

    private let claude = ClaudeService()

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
                sentiment[ticker]     = data
                lastFetchedAt[ticker] = Date()

                if !data.topMessages.isEmpty {
                    Task { await analyzeWithClaude(symbol: ticker, messages: data.topMessages) }
                }
            }
        }

        isFetching = false
    }

    func analyzeWithClaude(symbol: String, messages: [String]) async {
        guard !messages.isEmpty else { return }
        isAnalyzing[symbol] = true

        let numbered = messages.prefix(10).enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        let prompt = """
        Here are the most recent social media posts about \(symbol):

        \(numbered)

        In 2-3 plain sentences: What is the dominant narrative? What specific catalysts are being discussed (regulation, whale moves, macro, earnings)? How could this crowd sentiment move \(symbol)'s price near-term? Be direct and specific. No markdown, no bold, no bullet points — plain sentences only.
        """

        do {
            let raw = try await claude.send(
                messages: [ClaudeService.APIMessage(role: "user", content: prompt)],
                system: "You are a concise financial analyst. Respond in 2-3 plain sentences only. No markdown formatting, no bold, no headers, no lists."
            )
            let insight = raw
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "##", with: "")
                .replacingOccurrences(of: "# ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if sentiment[symbol] != nil {
                sentiment[symbol]?.claudeInsight = insight
            }
        } catch {
            // Graceful failure — leave claudeInsight nil
        }

        isAnalyzing[symbol] = false
    }

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

            let topMessages = messages.prefix(10).compactMap { $0.body }.filter { !$0.isEmpty }

            return SentimentData(
                symbol:      ticker,
                score:       score,
                label:       label,
                mentions:    mentions,
                topMessages: topMessages,
                updatedAt:   .now
            )
        } catch { return nil }
    }
}
