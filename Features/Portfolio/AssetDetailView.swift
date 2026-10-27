import SwiftUI
import Charts

struct AssetDetailView: View {
    @ObservedObject var asset: Asset
    @EnvironmentObject private var priceService:     PriceService
    @EnvironmentObject private var sentimentService: SentimentService
    @EnvironmentObject private var signalService:    QuantSignalService
    @Environment(\.managedObjectContext) private var ctx
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.dismiss) private var dismiss

    @FetchRequest private var activeAlerts: FetchedResults<PriceAlert>

    @State private var showingAddAlert    = false
    @State private var editingAlert: PriceAlert? = nil
    @State private var priceHistory: [PricePoint] = []
    @State private var historyLoading = false
    @State private var socialTab = 0
    @State private var showingLogTrade = false

    init(asset: Asset) {
        self.asset = asset
        self._activeAlerts = FetchRequest(
            sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)],
            predicate: NSPredicate(format: "symbol == %@ AND isActive == YES", asset.wrappedSymbol),
            animation: .default
        )
    }

    private var currentPrice: Double? { priceService.prices[asset.wrappedSymbol] }
    private var dailyChange: Double?  { priceService.changes[asset.wrappedSymbol] }

    private var currentValue: Double {
        (currentPrice ?? asset.avgCost) * asset.quantity
    }
    private var unrealizedPnL: Double {
        guard let price = currentPrice else { return 0 }
        return asset.unrealisedPnL(currentPrice: price)
    }
    private var unrealizedPnLPct: Double {
        guard let price = currentPrice else { return 0 }
        return asset.unrealisedPnLPercent(currentPrice: price)
    }
    private var hasCurrent: Bool { currentPrice != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.s16) {

                // MARK: Hero — asset icon + name
                VStack(spacing: Theme.s8) {
                    Image(systemName: asset.assetKind.icon)
                        .font(.system(size: 40))
                        .foregroundStyle(Color.ledgerAccent)
                        .frame(width: 72, height: 72)
                        .background(Color.ledgerAccent.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: Theme.radiusM))

                    Text(asset.wrappedSymbol)
                        .font(.title2.bold())

                    if !asset.wrappedName.isEmpty && asset.wrappedName != asset.wrappedSymbol {
                        Text(asset.wrappedName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(asset.assetKind.displayName)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color.ledgerAccent.opacity(0.1), in: Capsule())
                        .foregroundStyle(Color.ledgerAccent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.s8)

                // MARK: Price history chart
                VStack(alignment: .leading, spacing: Theme.s8) {
                    Text("1-Month Price History")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.s16)
                        .padding(.top, Theme.s16)

                    if historyLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 100)
                    } else if priceHistory.isEmpty {
                        Text("Price history unavailable")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 100)
                    } else {
                        let isUp = (priceHistory.last?.price ?? 0) >= (priceHistory.first?.price ?? 0)
                        let chartColor = isUp ? Color.ledgerPositive : Color.ledgerNegative
                        let minPrice = priceHistory.map(\.price).min() ?? 0
                        let maxPrice = priceHistory.map(\.price).max() ?? 1

                        Chart(priceHistory) { point in
                            LineMark(
                                x: .value("Date",  point.date),
                                y: .value("Price", point.price)
                            )
                            .foregroundStyle(chartColor)
                            .interpolationMethod(.monotone)

                            AreaMark(
                                x: .value("Date",  point.date),
                                yStart: .value("Min", minPrice),
                                yEnd:   .value("Price", point.price)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [chartColor.opacity(0.25), chartColor.opacity(0)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.monotone)
                        }
                        .chartYScale(domain: (minPrice * 0.995)...(maxPrice * 1.005))
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(height: 100)
                        .padding(.horizontal, Theme.s8)
                        .padding(.bottom, Theme.s8)
                    }
                }
                .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))

                // MARK: P&L card
                VStack(spacing: Theme.s12) {
                    Text("Unrealized P&L")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if hasCurrent {
                        Text((unrealizedPnL >= 0 ? "+" : "") + unrealizedPnL.asCurrency(code: currencyCode))
                            .font(Theme.monoTitle2())
                            .foregroundStyle(Color.changeColor(for: unrealizedPnL))

                        HStack(spacing: Theme.s8) {
                            Label(unrealizedPnLPct.asChangePercent(), systemImage:
                                    unrealizedPnL >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.subheadline.bold())
                                .foregroundStyle(Color.changeColor(for: unrealizedPnL))

                            if let dc = dailyChange {
                                Text("·")
                                    .foregroundStyle(.quaternary)
                                Text("Today: \(dc.asChangePercent())")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.changeColor(for: dc))
                            }
                        }
                    } else {
                        Text("—")
                            .font(Theme.monoTitle2())
                            .foregroundStyle(.secondary)
                        Text("No live price")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(Theme.s16)
                .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))

                // MARK: Bot Signal Card
                if let sig = signalService.signals[asset.wrappedSymbol] {
                    tradingSignalCard(sig)
                }

                // MARK: Social Sentiment + Posts
                if let s = sentimentService.sentiment[asset.wrappedSymbol] {
                    let analyzing = sentimentService.isAnalyzing[asset.wrappedSymbol] == true
                    VStack(alignment: .leading, spacing: Theme.s12) {
                        HStack(spacing: Theme.s8) {
                            Label("Social Sentiment", systemImage: "person.2.wave.2")
                                .font(.subheadline.bold())
                            Spacer()
                            Picker("", selection: $socialTab) {
                                Text("Summary").tag(0)
                                Text("Posts").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 150)
                        }

                        if socialTab == 0 {
                            // Summary tab: score bar + Market Intelligence
                            HStack(spacing: Theme.s16) {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color(.systemFill))
                                            .frame(height: 6)
                                        let pct = (s.score + 1) / 2
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(s.label.color)
                                            .frame(width: geo.size.width * pct, height: 6)
                                    }
                                }
                                .frame(height: 6)
                                SentimentBadge(data: s)
                            }

                            HStack {
                                Text("\(s.mentions) watching")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("via StockTwits")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            if analyzing || s.claudeInsight != nil {
                                Divider()
                                HStack(spacing: Theme.s8) {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(Color.ledgerAccent)
                                    Text("Market Intelligence")
                                        .font(.caption.bold())
                                        .foregroundStyle(Color.ledgerAccent)
                                    Spacer()
                                    Text("AI")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.ledgerAccent.opacity(0.12), in: Capsule())
                                        .foregroundStyle(Color.ledgerAccent)
                                }
                                if analyzing {
                                    HStack(spacing: Theme.s8) {
                                        ProgressView().scaleEffect(0.8)
                                        Text("Reading the crowd...")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                } else if let insight = s.claudeInsight {
                                    Text(insight)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineSpacing(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        } else {
                            // Posts tab: StockTwits message feed
                            if s.posts.isEmpty {
                                Text("No recent posts")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Theme.s8)
                            } else {
                                let visiblePosts = Array(s.posts.prefix(10))
                                VStack(spacing: 0) {
                                    ForEach(visiblePosts) { post in
                                        stockTwitsPostRow(post)
                                        if post.id != visiblePosts.last?.id {
                                            Divider().padding(.leading, 44)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(Theme.s16)
                    .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
                }

                // MARK: Price Alerts
                let alerts = activeAlerts
                VStack(alignment: .leading, spacing: Theme.s12) {
                    HStack {
                        Label("Price Alerts", systemImage: "bell.badge")
                            .font(.subheadline.bold())
                        Spacer()
                        Button {
                            showingAddAlert = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.ledgerAccent)
                        }
                    }

                    if alerts.isEmpty {
                        Text("No active alerts. Tap + to add one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(alerts) { alert in
                            HStack {
                                Image(systemName: alert.alertCondition.icon)
                                    .foregroundStyle(Color.ledgerAccent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(alert.alertCondition.displayName) \(alert.targetPrice.asCurrency(code: currencyCode))")
                                        .font(.subheadline)
                                    if !alert.wrappedNote.isEmpty {
                                        Text(alert.wrappedNote)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button {
                                    editingAlert = alert
                                } label: {
                                    Image(systemName: "pencil.circle")
                                        .foregroundStyle(.secondary)
                                }
                                Button(role: .destructive) {
                                    alert.isActive = false
                                    try? ctx.save()
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(.ledgerNegative)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Theme.s16)
                .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))

                // MARK: Metrics grid
                VStack(spacing: 0) {
                    metricRow(
                        label: "Current Price",
                        value: currentPrice.map { $0.asCurrency(code: currencyCode) } ?? "—",
                        valueColor: .primary
                    )
                    Divider().padding(.leading, Theme.s16)
                    metricRow(
                        label: "Avg Cost / Unit",
                        value: asset.avgCost.asCurrency(code: currencyCode),
                        valueColor: .primary
                    )
                    Divider().padding(.leading, Theme.s16)
                    metricRow(
                        label: "Quantity",
                        value: String(format: "%g", asset.quantity),
                        valueColor: .primary
                    )
                    Divider().padding(.leading, Theme.s16)
                    metricRow(
                        label: "Total Cost Basis",
                        value: asset.costBasis.asCurrency(code: currencyCode),
                        valueColor: .primary
                    )
                    Divider().padding(.leading, Theme.s16)
                    metricRow(
                        label: "Current Value",
                        value: currentValue.asCurrency(code: currencyCode),
                        valueColor: hasCurrent ? Color.changeColor(for: unrealizedPnL) : .primary
                    )
                }
                .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
            }
            .padding(Theme.s16)
        }
        .navigationTitle(asset.wrappedSymbol)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.ledgerGrouped)
        .sheet(isPresented: $showingAddAlert) {
            AddEditPriceAlertView(symbol: asset.wrappedSymbol)
                .environment(\.managedObjectContext, ctx)
        }
        .sheet(item: $editingAlert) { alert in
            AddEditPriceAlertView(symbol: asset.wrappedSymbol, alert: alert)
                .environment(\.managedObjectContext, ctx)
        }
        .sheet(isPresented: $showingLogTrade) {
            logTradeSheet
        }
        .task {
            historyLoading = true
            priceHistory = await priceService.fetchHistory(symbol: asset.wrappedSymbol, kind: asset.assetKind)
            historyLoading = false
        }
        .task {
            await sentimentService.fetch(symbols: [asset.wrappedSymbol])
        }
        .task {
            await signalService.fetch(symbols: [asset.wrappedSymbol])
        }
        // Re-run Market Intelligence with signal context once both sentiment + signal are available.
        .task(id: signalService.signals[asset.wrappedSymbol]?.fetchedAt) {
            guard let sig = signalService.signals[asset.wrappedSymbol],
                  let s   = sentimentService.sentiment[asset.wrappedSymbol],
                  !s.topMessages.isEmpty
            else { return }
            await sentimentService.analyzeWithClaude(
                symbol:        asset.wrappedSymbol,
                messages:      s.topMessages,
                signalContext: buildSignalContext(sig)
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if priceService.isLoading {
                    ProgressView()
                } else {
                    Button {
                        Task { await priceService.refresh(assets: [asset]) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    // MARK: - Trading Signal Card

    private func tradingSignalCard(_ sig: QuantSignal) -> some View {
        VStack(alignment: .leading, spacing: Theme.s12) {
            HStack(spacing: Theme.s8) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(Color.ledgerAccent)
                Text("Bot Signal")
                    .font(.subheadline.bold())
                Spacer()
                Text("PAPER")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.orange, in: Capsule())
            }

            // Social spike warning — shown prominently when active
            if sig.socialSpike {
                HStack(spacing: Theme.s8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Social volume spike detected — bot skipping entry")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
                .padding(Theme.s8)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusS))
            }

            // Position + z-score row
            HStack(spacing: Theme.s12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Position")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text(sig.position.uppercased())
                        .font(.subheadline.bold())
                        .foregroundStyle(positionColor(sig.position))
                }
                Divider().frame(height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Z-Score")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text(String(format: "%+.2f", sig.zScore))
                        .font(Theme.monoSubhead().bold())
                        .foregroundStyle(abs(sig.zScore) >= 2.0 ? Color.ledgerNegative : .primary)
                }
                if let sz = sig.socialZ {
                    Divider().frame(height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Social Z")
                            .font(.caption2).foregroundStyle(.tertiary)
                        Text(String(format: "%+.2f", sz))
                            .font(Theme.monoSubhead())
                            .foregroundStyle(abs(sz) >= 2.0 ? .orange : .secondary)
                    }
                }
                Spacer()
            }

            // Paper summary strip
            if let ps = sig.paperSummary {
                Divider()
                HStack(spacing: 0) {
                    paperStatCell(label: "Trades", value: "\(ps.nTrades)")
                    Divider().frame(height: 24)
                    let sign = ps.meanBps >= 0 ? "+" : ""
                    paperStatCell(label: "Avg", value: "\(sign)\(String(format: "%.1f", ps.meanBps)) bps",
                                  color: Color.changeColor(for: ps.meanBps))
                    Divider().frame(height: 24)
                    paperStatCell(label: "Win Rate", value: "\(Int(ps.winRate * 100))%",
                                  color: ps.winRate >= 0.5 ? .ledgerPositive : .ledgerNegative)
                }
                .padding(.vertical, Theme.s4)
                .background(Color(.secondarySystemFill).opacity(0.5),
                            in: RoundedRectangle(cornerRadius: Theme.radiusS))
            }

            HStack {
                Text("Updated \(sig.barTime, style: .relative) ago")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text("via ledger-proxy")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Button {
                HapticService.impact(.medium)
                showingLogTrade = true
            } label: {
                Label("Log Trade", systemImage: "plus.circle.fill")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.s8)
                    .background(Color.ledgerAccent.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: Theme.radiusS))
                    .foregroundStyle(Color.ledgerAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.s16)
        .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusM)
                .stroke(Color.ledgerAccent.opacity(0.15), lineWidth: 1)
        )
    }

    private func paperStatCell(label: String, value: String, color: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(.tertiary)
            Text(value).font(Theme.monoCaption().bold()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.s4)
    }

    private func positionColor(_ position: String) -> Color {
        switch position.lowercased() {
        case "long":  return .ledgerPositive
        case "short": return .ledgerNegative
        default:      return .secondary
        }
    }

    private func buildSignalContext(_ sig: QuantSignal) -> String {
        var parts = [
            "position=\(sig.position)",
            "z_score=\(String(format: "%.2f", sig.zScore))",
            "social_spike=\(sig.socialSpike)"
        ]
        if let ps = sig.paperSummary {
            parts.append("paper_mean=\(String(format: "%.1f", ps.meanBps)) bps over \(ps.nTrades) trades")
        }
        return "Current signal state for \(sig.symbol): \(parts.joined(separator: ", "))"
    }

    private func stockTwitsPostRow(_ post: StockTwitsPost) -> some View {
        HStack(alignment: .top, spacing: Theme.s12) {
            Text(String(post.username.prefix(1)).uppercased())
                .font(.caption.bold())
                .foregroundStyle(Color.ledgerAccent)
                .frame(width: 28, height: 28)
                .background(Color.ledgerAccent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.s4) {
                    Text("@\(post.username)").font(.caption.bold())
                    if let sentiment = post.sentiment {
                        Text(sentiment.rawValue)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(sentiment.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(sentiment.color)
                    }
                    Spacer()
                    Text(post.createdAt, style: .relative)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Text(post.body)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, Theme.s8)
    }

    @ViewBuilder
    private var logTradeSheet: some View {
        if let sig = signalService.signals[asset.wrappedSymbol] {
            let dir: TradeDirection = sig.position == "short" ? .short : .long
            AddEditJournalEntryView(
                prefillSymbol:      asset.wrappedSymbol,
                prefillDirection:   dir,
                prefillStrategyTag: "bot-signal",
                prefillNotes:       buildLogNotes(sig)
            )
            .environment(\.managedObjectContext, ctx)
        }
    }

    private func buildLogNotes(_ sig: QuantSignal) -> String {
        var lines = ["Bot signal · z\(sig.zScore >= 0 ? "+" : "")\(String(format: "%.2f", sig.zScore)) · \(sig.position.uppercased())"]
        if let ps = sig.paperSummary {
            lines.append("\(ps.nTrades) trades · \(Int(ps.winRate * 100))% win · \(String(format: "%+.1f", ps.meanBps)) bps avg")
        }
        if sig.socialSpike { lines.append("⚠ Social spike active at entry") }
        return lines.joined(separator: "\n")
    }

    private func metricRow(label: String, value: String, valueColor: Color) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(Theme.monoSubhead())
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, Theme.s16)
        .padding(.vertical, Theme.s12)
    }
}

#Preview {
    let ctx = PersistenceController.preview.container.viewContext
    let asset = try! ctx.fetch(Asset.fetchRequest()).first!
    return NavigationStack {
        AssetDetailView(asset: asset)
    }
    .environment(\.managedObjectContext, ctx)
    .environmentObject(PriceService())
    .environmentObject(SentimentService())
    .environmentObject(QuantSignalService())
}
