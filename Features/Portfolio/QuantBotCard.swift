import SwiftUI

// Live quant-system summary card in PortfolioView.
// Tapping opens the full Bots tab. Data source: https://quant-system-live.netlify.app/status.json

struct QuantBotCard: View {
    @EnvironmentObject private var quantStatus: QuantStatusService
    /// Binding to ContentView's selectedTab so tapping deep-links to the Bots tab (tag 3).
    var onTapOpenBots: (() -> Void)? = nil

    var body: some View {
        Button {
            onTapOpenBots?()
        } label: {
            VStack(alignment: .leading, spacing: Theme.s12) {
                header
                if quantStatus.isFetching {
                    loadingSkeleton
                } else if let status = quantStatus.status {
                    equityRow(status: status)
                    Divider()
                    stanceRow(status: status)
                    footer(status: status)
                } else if quantStatus.lastError != nil {
                    Label("Bot status unavailable — check connection", systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Bot data loading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Deep-link hint
                HStack {
                    Spacer()
                    Label("See full bot data", systemImage: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.ledgerAccent)
                }
            }
            .padding(Theme.s16)
            .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
        }
        .buttonStyle(ScaleButtonStyle(pressedScale: 0.98))
        .disabled(onTapOpenBots == nil)
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack(alignment: .center) {
            Label("Quant Bots", systemImage: "bolt.fill")
                .font(.subheadline.bold())
            Spacer()
            if let strategy = quantStatus.status?.activeStrategy {
                Text(strategyLabel(strategy))
                    .font(.caption2.bold())
                    .foregroundStyle(Color.ledgerAccent)
                    .padding(.horizontal, Theme.s8)
                    .padding(.vertical, 3)
                    .background(Color.ledgerAccent.opacity(0.12), in: Capsule())
            }
            if quantStatus.isFetching {
                ProgressView().scaleEffect(0.75)
            }
        }
    }

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: Theme.s8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemFill))
                .frame(height: 28)
            HStack(spacing: Theme.s8) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.radiusS)
                        .fill(Color(.systemFill))
                        .frame(height: 40)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .redacted(reason: .placeholder)
        .shimmering()
    }

    private func equityRow(status: QuantStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.s8) {
            if let eq = status.equityMain {
                Text(eq.asCurrency(code: "USD"))
                    .font(Theme.monoTitle2())
            }
            Spacer()
            if let pnl = status.dailyPnlMain {
                let sign = pnl >= 0 ? "+" : ""
                let pct: Double = {
                    guard let eq = status.equityMain else { return 0 }
                    let prev = eq - pnl
                    return prev > 0 ? (pnl / prev * 100) : 0
                }()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(sign)\(pnl.asCurrency(code: "USD"))")
                        .font(Theme.monoCaption().bold())
                        .foregroundStyle(Color.changeColor(for: pnl))
                    Text("\(sign)\(String(format: "%.2f", pct))%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.changeColor(for: pnl))
                }
            }
        }
    }

    private func stanceRow(status: QuantStatus) -> some View {
        let sorted = (status.stances ?? [:]).sorted { $0.key < $1.key }
        return HStack(spacing: Theme.s8) {
            ForEach(sorted, id: \.key) { symbol, stance in
                VStack(spacing: 2) {
                    Text(coinTicker(symbol))
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text(stance)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(stanceColor(stance))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.horizontal, Theme.s8)
                .padding(.vertical, Theme.s4)
                .background(stanceColor(stance).opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusS))
                if sorted.last?.key != symbol { Spacer() }
            }
            if sorted.isEmpty {
                Text("No stance data").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func footer(status: QuantStatus) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let ts = status.updatedAt {
                Text("Updated \(relativeTime(ts))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Helpers

    private func strategyLabel(_ strategy: String) -> String {
        switch strategy.lowercased() {
        case "trend":     return "200-day trend"
        case "consensus": return "consensus"
        default:          return strategy
        }
    }

    private func coinTicker(_ brokerSymbol: String) -> String {
        brokerSymbol.components(separatedBy: "/").first ?? brokerSymbol
    }

    private func stanceColor(_ stance: String) -> Color {
        switch stance.uppercased() {
        case "HOLDING", "LONG": return Color.ledgerPositive
        case "IN CASH", "FLAT": return Color.secondary
        case "EMERGENCY STOP":  return Color.ledgerNegative
        default:                return Color.secondary
        }
    }

    private func relativeTime(_ isoString: String) -> String { isoString.relativeTimeAgo }
}


#Preview {
    QuantBotCard()
        .environmentObject(QuantStatusService())
        .padding()
        .background(Color.ledgerGrouped)
}
