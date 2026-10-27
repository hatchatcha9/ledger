import Foundation

// MARK: - Models

struct QuantSignal {
    let symbol:       String
    let barTime:      Date
    let close:        Double
    let zScore:       Double
    let socialZ:      Double?
    let socialSpike:  Bool
    let position:     String    // "flat", "long", "short"
    let action:       String
    let paperSummary: PaperSummary?
    let fetchedAt:    Date

    struct PaperSummary {
        let nTrades:     Int
        let meanBps:     Double
        let winRate:     Double
        let lastUpdated: Date
    }
}

// MARK: - Decodable response

private struct SignalResponse: Decodable {
    let symbol:       String
    let barTime:      String?
    let close:        Double?
    let zScore:       Double?
    let socialZ:      Double?
    let socialSpike:  Bool?
    let position:     String?
    let action:       String?
    let paperSummary: PaperSummaryResponse?

    struct PaperSummaryResponse: Decodable {
        let nTrades:     Int?
        let meanBps:     Double?
        let winRate:     Double?
        let lastUpdated: String?
        enum CodingKeys: String, CodingKey {
            case nTrades     = "n_trades"
            case meanBps     = "mean_bps"
            case winRate     = "win_rate"
            case lastUpdated = "last_updated"
        }
    }

    enum CodingKeys: String, CodingKey {
        case symbol
        case barTime     = "bar_time"
        case close
        case zScore      = "z_score"
        case socialZ     = "social_z"
        case socialSpike = "social_spike"
        case position
        case action
        case paperSummary = "paper_summary"
    }
}

// MARK: - Service

@MainActor
final class QuantSignalService: ObservableObject {
    @Published private(set) var signals:   [String: QuantSignal] = [:]
    @Published private(set) var isFetching = false
    @Published private(set) var lastError: String?

    private var lastFetchedAt: [String: Date] = [:]
    private static let cacheTTL: TimeInterval = 300  // 5 min, matches paper logger push cadence

    func fetch(symbols: [String]) async {
        let stale = symbols.filter {
            guard let last = lastFetchedAt[$0] else { return true }
            return Date().timeIntervalSince(last) > Self.cacheTTL
        }
        guard !stale.isEmpty else { return }

        isFetching = true
        lastError  = nil
        for symbol in stale {
            if let signal = await fetchSignal(symbol: symbol) {
                signals[symbol]       = signal
                lastFetchedAt[symbol] = Date()
            }
        }
        isFetching = false
    }

    private nonisolated func fetchSignal(symbol: String) async -> QuantSignal? {
        // Strip pair notation: "BTC/USD" → "BTC"
        let sym = symbol.components(separatedBy: "/").first ?? symbol
        guard let url = URL(string: "\(ClaudeProxySecrets.proxyBaseURL)/api/quant/signal/\(sym)")
        else { return nil }

        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }

            let decoded = try JSONDecoder().decode(SignalResponse.self, from: data)
            let isoFmt  = ISO8601DateFormatter()

            let summary: QuantSignal.PaperSummary? = decoded.paperSummary.map { ps in
                QuantSignal.PaperSummary(
                    nTrades:     ps.nTrades ?? 0,
                    meanBps:     ps.meanBps ?? 0,
                    winRate:     ps.winRate ?? 0,
                    lastUpdated: ps.lastUpdated.flatMap { isoFmt.date(from: $0) } ?? Date()
                )
            }

            return QuantSignal(
                symbol:       sym,
                barTime:      decoded.barTime.flatMap { isoFmt.date(from: $0) } ?? Date(),
                close:        decoded.close ?? 0,
                zScore:       decoded.zScore ?? 0,
                socialZ:      decoded.socialZ,
                socialSpike:  decoded.socialSpike ?? false,
                position:     decoded.position ?? "flat",
                action:       decoded.action ?? "hold",
                paperSummary: summary,
                fetchedAt:    Date()
            )
        } catch { return nil }
    }
}
