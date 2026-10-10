import Foundation

// Fetches the live quant-system status JSON published by the quant-system repo.
// URL: https://quant-system-live.netlify.app/status.json
// Falls back gracefully when offline — last fetched value is retained.

struct QuantStatus: Codable {
    let updatedAt:            String?
    let equityMain:           Double?
    let equityMini:           Double?
    let dailyPnlMain:         Double?
    let stances:              [String: String]?   // e.g. {"BTC":"long","ETH":"flat"}
    let activeStrategy:       String?
    let forwardTestsVerdict:  String?
    let researchSummary:      String?

    enum CodingKeys: String, CodingKey {
        case updatedAt           = "updated_at"
        case equityMain          = "equity_main"
        case equityMini          = "equity_mini"
        case dailyPnlMain        = "daily_pnl_main"
        case stances
        case activeStrategy      = "active_strategy"
        case forwardTestsVerdict = "forward_tests_verdict"
        case researchSummary     = "research_summary"
    }

    // Human-readable summary injected into the Claude system prompt.
    var contextString: String {
        var lines = [String]()

        if let eq = equityMain {
            lines.append("  Main account equity: $\(String(format: "%.2f", eq))")
        }
        if let eq = equityMini {
            lines.append("  Mini account equity: $\(String(format: "%.2f", eq))")
        }
        if let pnl = dailyPnlMain {
            let sign = pnl >= 0 ? "+" : ""
            lines.append("  Today's P&L (main): \(sign)$\(String(format: "%.2f", pnl))")
        }
        if let stances, !stances.isEmpty {
            let stanceStr = stances.sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            lines.append("  Current stances: \(stanceStr)")
        }
        if let strategy = activeStrategy {
            let label: String
            switch strategy.lowercased() {
            case "trend":     label = "200-day trend filter"
            case "consensus": label = "consensus (trend + momentum)"
            default:          label = strategy
            }
            lines.append("  Active strategy: \(label)")
        }
        if let verdict = forwardTestsVerdict {
            lines.append("  Forward test verdict: \(verdict)")
        }
        if let research = researchSummary, !research.isEmpty {
            lines.append("  Latest research: \(research)")
        }
        if let ts = updatedAt {
            lines.append("  (Status last updated: \(ts))")
        }

        return lines.joined(separator: "\n")
    }
}

@MainActor
final class QuantStatusService: ObservableObject {
    static let statusURL = URL(string: "https://quant-system-live.netlify.app/status.json")!

    @Published private(set) var status: QuantStatus?
    @Published private(set) var lastError: String?
    @Published private(set) var isFetching = false

    func fetch() async {
        guard !isFetching else { return }
        isFetching = true
        lastError  = nil

        do {
            var req = URLRequest(url: Self.statusURL)
            req.timeoutInterval = 8   // don't linger on slow responses
            let (data, _) = try await URLSession.shared.data(for: req)
            status = try JSONDecoder().decode(QuantStatus.self, from: data)
        } catch {
            lastError = error.localizedDescription
        }

        isFetching = false
    }
}
