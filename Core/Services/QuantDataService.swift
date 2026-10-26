import Foundation

// Fetches the full quant snapshot (data.json) and CoinGecko OHLC candles.
// data.json: https://quant-system-live.netlify.app/data.json
// CoinGecko OHLC: https://api.coingecko.com/api/v3/coins/{id}/ohlc?vs_currency=usd&days=7

// MARK: - Shared formatter

private let _iso8601 = ISO8601DateFormatter()

// MARK: - Data models

struct EquityPoint: Identifiable, Decodable {
    var id: String { t }
    let t:      String
    let equity: Double

    var date: Date { _iso8601.date(from: t) ?? .distantPast }
}

struct BotDecision: Identifiable, Decodable {
    var id: String { ts }
    let ts:             String
    let price:          Double
    let action:         String
    let orderStatus:    String?
    let stance:         String?
    let reason:         String?
    let emergencyStop:  Bool?

    enum CodingKeys: String, CodingKey {
        case ts, price, action
        case orderStatus    = "order_status"
        case stance
        case reason
        case emergencyStop  = "emergency_stop"
    }

    var date: Date { _iso8601.date(from: ts) ?? .distantPast }

    var isSubmitted: Bool { action == "submitted" }
    // Buy = bot entered or held a long position; sell = bot exited to cash
    var isBuy: Bool {
        guard let s = stance else { return false }
        return s == "LONG" || s == "HOLDING"
    }
}

struct BotCoin: Identifiable, Decodable {
    var id: String { symbol }
    let symbol:         String
    let positionQty:    Double?
    let positionValue:  Double?
    let unrealizedPl:   Double?
    let decisions:      [BotDecision]

    enum CodingKeys: String, CodingKey {
        case symbol
        case positionQty    = "position_qty"
        case positionValue  = "position_value"
        case unrealizedPl   = "unrealized_pl"
        case decisions
    }

    var ticker: String { symbol.components(separatedBy: "/").first ?? symbol }
}

struct FeedEvent: Identifiable, Decodable {
    var id: String { "\(symbol)_\(ts)" }
    let ts:             String
    let symbol:         String
    let price:          Double
    let action:         String
    let orderStatus:    String?
    let stance:         String?
    let reason:         String?
    let emergencyStop:  Bool?

    enum CodingKeys: String, CodingKey {
        case ts, symbol, price, action
        case orderStatus   = "order_status"
        case stance
        case reason
        case emergencyStop = "emergency_stop"
    }

    var date: Date { _iso8601.date(from: ts) ?? .distantPast }
    var ticker: String { symbol.components(separatedBy: "/").first ?? symbol }
}

struct QuantSnapshot: Decodable {
    let generatedAt:  String?
    let strategy:     String?
    let equityCurve:  [EquityPoint]
    let coins:        [BotCoin]
    let feed:         [FeedEvent]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case strategy
        case equityCurve = "equity_curve"
        case coins
        case feed
    }
}

// MARK: - Candle

struct OHLCCandle: Identifiable, Equatable {
    let id    = UUID()
    let date:  Date
    let open:  Double
    let high:  Double
    let low:   Double
    let close: Double

    var isBullish: Bool { close >= open }

    static func == (lhs: OHLCCandle, rhs: OHLCCandle) -> Bool { lhs.id == rhs.id }
}

// MARK: - Service

@MainActor
final class QuantDataService: ObservableObject {
    static let dataURL   = URL(string: "https://quant-system-live.netlify.app/data.json")!
    static let geckoBase = "https://api.coingecko.com/api/v3/coins"

    static let geckoIDs: [String: String] = [
        "BTC/USD": "bitcoin",
        "ETH/USD": "ethereum",
        "SOL/USD": "solana",
    ]

    @Published private(set) var snapshot:     QuantSnapshot?
    @Published private(set) var candles:      [String: [OHLCCandle]] = [:]  // keyed by broker symbol
    @Published private(set) var isFetching    = false
    @Published private(set) var lastError:    String?

    private var lastFetchedAt: Date?
    private static let cacheTTL: TimeInterval = 300   // 5 minutes

    var isStale: Bool {
        guard let last = lastFetchedAt else { return true }
        return Date().timeIntervalSince(last) > Self.cacheTTL
    }

    func fetchAll(force: Bool = false) async {
        guard !isFetching else { return }
        guard force || isStale else { return }    // skip if fresh
        isFetching = true
        lastError  = nil

        async let snapTask = fetchSnapshot()
        async let btcTask  = fetchCandles(for: "BTC/USD", days: 7)
        async let ethTask  = fetchCandles(for: "ETH/USD", days: 7)
        async let solTask  = fetchCandles(for: "SOL/USD", days: 7)

        snapshot         = await snapTask
        candles["BTC/USD"] = await btcTask
        candles["ETH/USD"] = await ethTask
        candles["SOL/USD"] = await solTask

        if snapshot == nil && candles.values.allSatisfy({ $0.isEmpty }) {
            lastError = "Could not load bot data — check connection"
        } else if snapshot != nil && candles.values.contains(where: { !$0.isEmpty }) {
            lastFetchedAt = Date()
        }

        isFetching = false
    }

    func fetchSnapshot() async -> QuantSnapshot? {
        do {
            var req = URLRequest(url: Self.dataURL)
            req.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: req)
            return try JSONDecoder().decode(QuantSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    func updateCandles(for symbol: String, candles: [OHLCCandle]) {
        self.candles[symbol] = candles
    }

    func fetchCandles(for symbol: String, days: Int) async -> [OHLCCandle] {
        guard let geckoID = Self.geckoIDs[symbol],
              let url = URL(string: "\(Self.geckoBase)/\(geckoID)/ohlc?vs_currency=usd&days=\(days)")
        else { return [] }

        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: req)
            // CoinGecko returns [[timestamp_ms, open, high, low, close]]
            let raw = try JSONDecoder().decode([[Double]].self, from: data)
            return raw.compactMap { arr -> OHLCCandle? in
                guard arr.count >= 5 else { return nil }
                return OHLCCandle(
                    date:  Date(timeIntervalSince1970: arr[0] / 1000),
                    open:  arr[1],
                    high:  arr[2],
                    low:   arr[3],
                    close: arr[4]
                )
            }
        } catch {
            return []
        }
    }
}
