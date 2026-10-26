import SwiftUI
import Charts

struct BotsView: View {
    @EnvironmentObject private var quantStatus: QuantStatusService
    @StateObject private var dataService = QuantDataService()

    @State private var selectedSymbol: String = "BTC/USD"
    @State private var selectedRange:  CandleRange = .sevenDays
    @State private var showingChat      = false
    @State private var researchExpanded = false
    @State private var feedExpanded    = false
    // chatVM is seeded once; not reset on sheet re-open so conversation persists
    @StateObject private var chatVM    = ChatViewModel()
    @State private var chatSeeded      = false

    private let symbols = ["BTC/USD", "ETH/USD", "SOL/USD"]
    private var isLoading: Bool { dataService.isFetching }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.s16) {
                    errorBanner
                    stalenessWarning
                    accountHeader
                    goLiveCard           // forward test verdict — prominent when available
                    equityCurveCard
                    positionsStrip       // positions ABOVE chart so tapping a card keeps chart visible
                    chartSection
                    feedCard
                    researchCard
                    askClaudeButton
                }
                .padding(Theme.s16)
                .padding(.bottom, 80)
            }
            .background(Color.ledgerGrouped)
            .navigationTitle("Bots")
            .refreshable {
                async let a: () = dataService.fetchAll(force: true)
                async let b: () = quantStatus.fetch()
                _ = await (a, b)
                chatSeeded = false   // re-seed Claude greeting with fresh data
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if dataService.isFetching {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button {
                            Task {
                                async let a: () = dataService.fetchAll(force: true)
                                async let b: () = quantStatus.fetch()
                                _ = await (a, b)
                                chatSeeded = false
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingChat) {
            ChatView(viewModel: chatVM)
        }
        .task {
            async let a: () = dataService.fetchAll()
            async let b: () = quantStatus.fetch()
            _ = await (a, b)
        }
    }

    // MARK: - Error banner

    @ViewBuilder
    private var errorBanner: some View {
        let err = dataService.lastError ?? quantStatus.lastError
        if let err, !isLoading {
            HStack(spacing: Theme.s8) {
                Image(systemName: "wifi.slash").font(.subheadline)
                Text(err).font(.caption).lineLimit(2)
                Spacer()
                Button("Retry") {
                    Task {
                        async let a: () = dataService.fetchAll(force: true)
                        async let b: () = quantStatus.fetch()
                        _ = await (a, b)
                    }
                }
                .font(.caption.bold())
            }
            .foregroundStyle(.white)
            .padding(Theme.s12)
            .background(Color.ledgerNegative, in: RoundedRectangle(cornerRadius: Theme.radiusS))
        }
    }

    // MARK: - Staleness warning

    @ViewBuilder
    private var stalenessWarning: some View {
        if let ts = quantStatus.status?.updatedAt,
           let date = ts.iso8601Date,
           -date.timeIntervalSinceNow > 7200 {   // >2 hours stale
            let hours = Int(-date.timeIntervalSinceNow / 3600)
            HStack(spacing: Theme.s8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Data \(hours)h old — bot status may be stale. Pull to refresh.")
                    .font(.caption)
                Spacer()
            }
            .padding(Theme.s12)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusS))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusS)
                    .stroke(Color.orange.opacity(0.4), lineWidth: 1)
            )
        }
    }

    // MARK: - Go Live? card

    @ViewBuilder
    private var goLiveCard: some View {
        if let verdict = quantStatus.status?.forwardTestsVerdict {
            let isPositive  = verdict.lowercased().contains("ready") || verdict.lowercased().contains("go") || verdict.lowercased().contains("pass")
            let isInProgress = verdict.lowercased().contains("progress") || verdict.lowercased().contains("running") || verdict.lowercased().contains("wait")
            let icon  = isPositive ? "checkmark.seal.fill" : isInProgress ? "timer" : "exclamationmark.triangle"
            let color: Color = isPositive ? .ledgerPositive : isInProgress ? .ledgerAccent : .ledgerNegative

            VStack(alignment: .leading, spacing: Theme.s8) {
                HStack(spacing: Theme.s8) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                    Text("Forward Test Verdict")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("PAPER ONLY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }

                Text(verdict)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                if let summary = quantStatus.status?.researchSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: Theme.s8) {
                    Image(systemName: "info.circle").font(.caption2).foregroundStyle(.secondary)
                    Text("Real-money deployment requires an explicit in-session go-ahead.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
            .padding(Theme.s16)
            .background(Color.ledgerAccent.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.radiusM))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusM)
                    .stroke(Color.ledgerAccent.opacity(0.2), lineWidth: 1.5)
            )
        }
    }

    // MARK: - Account header

    private var accountHeader: some View {
        VStack(alignment: .leading, spacing: Theme.s8) {
            if isLoading && quantStatus.status == nil {
                VStack(alignment: .leading, spacing: Theme.s8) {
                    skeletonRect(width: 100, height: 12).cornerRadius(3)
                    skeletonRect(width: 180, height: 32).cornerRadius(3)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        // PAPER badge — prominently visible so simulated-money status is unmissable
                        HStack(spacing: Theme.s4) {
                            Text("PAPER")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange, in: Capsule())
                            Text("Account")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(quantStatus.status?.equityMain.map { $0.asCurrency(code: "USD") } ?? "—")
                            .font(Theme.monoTitle2())
                    }
                    Spacer()
                    if let pnl = quantStatus.status?.dailyPnlMain,
                       let equity = quantStatus.status?.equityMain {
                        let prev = equity - pnl
                        let pct  = prev > 0 ? (pnl / prev * 100) : 0
                        let sign = pnl >= 0 ? "+" : ""
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(sign)\(pnl.asCurrency(code: "USD"))")
                                .font(Theme.monoSubhead().bold())
                                .foregroundStyle(Color.changeColor(for: pnl))
                            Text("\(sign)\(String(format: "%.2f", pct))%")
                                .font(.caption2)
                                .foregroundStyle(Color.changeColor(for: pnl))
                        }
                        .padding(.horizontal, Theme.s8)
                        .padding(.vertical, 5)
                        .background(Color.changeColor(for: pnl).opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusS))
                    }
                }

                HStack(spacing: Theme.s8) {
                    if let strategy = quantStatus.status?.activeStrategy {
                        Text(strategyLabel(strategy))
                            .font(.caption2.bold())
                            .foregroundStyle(.ledgerAccent)
                            .padding(.horizontal, Theme.s8)
                            .padding(.vertical, 3)
                            .background(Color.ledgerAccent.opacity(0.1), in: Capsule())
                    }
                    let tradeCount = allDecisions.filter { $0.isSubmitted }.count
                    if tradeCount > 0 {
                        Text("\(tradeCount) orders (all time)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if let ts = quantStatus.status?.updatedAt {
                        Text(ts.relativeTimeAgo)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(Theme.s16)
        .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
    }

    // MARK: - Equity curve card

    @ViewBuilder
    private var equityCurveCard: some View {
        let curve = dataService.snapshot?.equityCurve ?? []
        // Only render the card when there's data to show or we're waiting for it
        if !curve.isEmpty || isLoading {
        VStack(alignment: .leading, spacing: Theme.s12) {
            Label("Account Equity", systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline.bold())

            if isLoading && curve.isEmpty {
                skeletonRect(width: nil, height: 140).cornerRadius(Theme.radiusS)
            } else {
                let isUp   = (curve.last?.equity ?? 0) >= (curve.first?.equity ?? 0)
                let color: Color = isUp ? .ledgerPositive : .ledgerNegative

                Chart(curve) { pt in
                    LineMark(
                        x: .value("Time",   pt.date),
                        y: .value("Equity", pt.equity)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))

                    AreaMark(
                        x: .value("Time",   pt.date),
                        y: .value("Equity", pt.equity)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [color.opacity(0.18), color.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    ))
                }
                .frame(height: 110)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Color(.separator).opacity(0.3))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(Color(.separator).opacity(0.3))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("$\(String(format: "%.0f", v))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Stats grid: total return + max drawdown (same period as curve)
                if let first = curve.first?.equity, let last = curve.last?.equity {
                    let totalPnl = last - first
                    let totalPct = first > 0 ? (totalPnl / first * 100) : 0
                    let maxDD    = maxDrawdown(curve)

                    // Date range label for the equity curve
                    if let startDate = curve.first?.date, let endDate = curve.last?.date {
                        HStack {
                            Image(systemName: "calendar").font(.system(size: 9)).foregroundStyle(.tertiary)
                            Text("\(startDate.formatted(.dateTime.month(.abbreviated).day())) – \(endDate.formatted(.dateTime.month(.abbreviated).day()))")
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                    }

                    HStack(spacing: 0) {
                        statsCell(
                            label: "Bot Total Return",
                            value: "\(totalPnl >= 0 ? "+" : "")\(String(format: "%.2f", totalPct))%",
                            color: Color.changeColor(for: totalPnl)
                        )
                        Divider().frame(height: 30)
                        statsCell(
                            label: "Max Drawdown",
                            value: "-\(String(format: "%.1f", maxDD * 100))%",
                            color: .secondary   // just data — no arbitrary red threshold
                        )
                    }
                    .padding(.vertical, Theme.s4)
                    .background(Color(.secondarySystemFill).opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.radiusS))

                    // BTC benchmark — clearly labeled as a different time window
                    if let bpct = btcBenchmarkReturn {
                        HStack(spacing: Theme.s4) {
                            Image(systemName: "arrow.left.arrow.right").font(.system(size: 9)).foregroundStyle(.secondary)
                            Text("BTC buy-and-hold (\(selectedRange.rawValue)):")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                            Text("\(bpct >= 0 ? "+" : "")\(String(format: "%.1f", bpct))%")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.changeColor(for: bpct))
                            Spacer()
                            Text("(chart range, not curve period)")
                                .font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, Theme.s4)
                    }
                }
            }
        }
        .padding(Theme.s16)
        .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
        } // end if !curve.isEmpty || isLoading
    }

    // MARK: - Positions strip

    private var positionsStrip: some View {
        let hasRealData = !(dataService.snapshot?.coins.isEmpty ?? true)
        return VStack(alignment: .leading, spacing: Theme.s8) {
            Text(hasRealData ? "Positions" : "Stances")
                .font(.subheadline.bold())

            if isLoading && !hasRealData && stanceCards.isEmpty {
                HStack(spacing: Theme.s12) {
                    ForEach(0..<3, id: \.self) { _ in
                        skeletonRect(width: 120, height: 80).cornerRadius(Theme.radiusM)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.s12) {
                        if hasRealData {
                            ForEach(dataService.snapshot!.coins) { coin in
                                positionCard(coin: coin)
                            }
                        } else {
                            ForEach(stanceCards, id: \.symbol) { item in
                                stanceOnlyCard(symbol: item.symbol, stance: item.stance)
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
        .padding(Theme.s16)
        .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
    }

    private func positionCard(coin: BotCoin) -> some View {
        let stance = quantStatus.status?.stances?[coin.symbol] ?? "—"
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedSymbol = coin.symbol }
        } label: {
            VStack(alignment: .leading, spacing: Theme.s4) {
                HStack {
                    Text(coin.ticker).font(.subheadline.bold())
                    Spacer()
                    Text(stance)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(stanceColor(stance))
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(stanceColor(stance).opacity(0.15), in: Capsule())
                }

                if let val = coin.positionValue, val > 0 {
                    Text(val.asCurrency(code: "USD")).font(Theme.monoSubhead())
                } else {
                    Text("No position").font(.caption2).foregroundStyle(.tertiary)
                }

                if let equity = coin.positionValue,
                   let pl     = coin.unrealizedPl, equity > 0 {
                    let cost    = equity - pl
                    let rawPct  = cost > 0 ? (pl / cost * 100) : 0
                    let pct     = max(-999, min(999, rawPct))   // cap display at ±999%
                    let sign    = pl >= 0 ? "+" : ""
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(sign)\(pl.asCurrency(code: "USD"))")
                            .font(Theme.monoCaption())
                            .foregroundStyle(Color.changeColor(for: pl))
                        Text("\(sign)\(String(format: "%.2f", pct))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.changeColor(for: pl))
                    }
                } else if let pl = coin.unrealizedPl {
                    let sign = pl >= 0 ? "+" : ""
                    Text("\(sign)\(pl.asCurrency(code: "USD"))")
                        .font(Theme.monoCaption())
                        .foregroundStyle(Color.changeColor(for: pl))
                }
            }
            .padding(Theme.s12)
            .frame(width: 120)
            .background(
                selectedSymbol == coin.symbol ? Color.ledgerAccent.opacity(0.1) : Color.ledgerSurface,
                in: RoundedRectangle(cornerRadius: Theme.radiusM)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusM)
                    .stroke(selectedSymbol == coin.symbol ? Color.ledgerAccent : Color(.separator).opacity(0.4), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func stanceOnlyCard(symbol: String, stance: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedSymbol = symbol }
        } label: {
            VStack(alignment: .leading, spacing: Theme.s4) {
                Text(symbol.components(separatedBy: "/").first ?? symbol).font(.subheadline.bold())
                Text(stance)
                    .font(.caption2.bold())
                    .foregroundStyle(stanceColor(stance))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("No position data")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(Theme.s12)
            .frame(width: 120)
            .background(
                selectedSymbol == symbol ? Color.ledgerAccent.opacity(0.1) : Color.ledgerSurface,
                in: RoundedRectangle(cornerRadius: Theme.radiusM)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusM)
                    .stroke(selectedSymbol == symbol ? Color.ledgerAccent : Color(.separator).opacity(0.4), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chart section (below positions)

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: Theme.s12) {
            HStack(alignment: .firstTextBaseline) {
                // Coin label — tap in the positions strip above to change coin
                VStack(alignment: .leading, spacing: 1) {
                    Text(selectedSymbol.components(separatedBy: "/").first ?? selectedSymbol)
                        .font(.subheadline.bold())
                    Text("Chart").font(.caption2).foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Range", selection: $selectedRange) {
                    ForEach(CandleRange.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .labelsHidden()
            }

            if isLoading && (dataService.candles[selectedSymbol] ?? []).isEmpty {
                skeletonRect(width: nil, height: 220).cornerRadius(Theme.radiusS)
            } else {
                CandlestickChartView(
                    candles:      candlesForRange,
                    decisions:    decisionsInRange,
                    symbol:       selectedSymbol,
                    range:        selectedRange,
                    currentPrice: candlesForRange.last?.close
                )

                if decisionsInRange.isEmpty && !candlesForRange.isEmpty {
                    Label("No bot activity in this period", systemImage: "clock.badge.questionmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Theme.s16)
        .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
        .onChange(of: selectedRange) { newRange in
            Task { await refetchCandlesIfNeeded(days: newRange.days) }
        }
    }

    // MARK: - Activity feed

    private var feedCard: some View {
        VStack(alignment: .leading, spacing: Theme.s12) {
            Text("Bot Activity").font(.subheadline.bold())

            let allEvents: [FeedEvent] = dataService.snapshot?.feed ?? []
            let displayEvents = feedExpanded ? allEvents : Array(allEvents.prefix(10))

            if isLoading && allEvents.isEmpty {
                VStack(spacing: Theme.s8) {
                    ForEach(0..<4, id: \.self) { _ in feedRowSkeleton }
                }
            } else if allEvents.isEmpty {
                Label("No recent activity", systemImage: "clock.badge.xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(displayEvents) { event in
                        feedRow(event: event)
                        if event.id != displayEvents.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }

                if allEvents.count > 10 {
                    Button {
                        withAnimation { feedExpanded.toggle() }
                    } label: {
                        HStack(spacing: Theme.s4) {
                            Text(feedExpanded ? "Show less" : "View all \(allEvents.count) events")
                            Image(systemName: feedExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.ledgerAccent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Theme.s4)
                }
            }
        }
        .padding(Theme.s16)
        .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
    }

    private func feedRow(event: FeedEvent) -> some View {
        HStack(spacing: Theme.s12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(feedColor(event))
                .frame(width: 4, height: 36)

            Image(systemName: feedIcon(event))
                .font(.footnote)
                .foregroundStyle(feedColor(event))
                .frame(width: 28, height: 28)
                .background(feedColor(event).opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusS))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.s4) {
                    Text(event.ticker).font(.subheadline.bold())
                    Text(event.action.capitalized).font(.caption).foregroundStyle(feedColor(event))
                }
                if let stance = event.stance {
                    Text(stance).font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                // Precision: ≥$1000 = whole dollars (BTC/ETH), <$1000 = 2 decimal places (SOL etc.)
                Text(event.price >= 1000
                     ? "$\(String(format: "%.0f", event.price))"
                     : "$\(String(format: "%.2f", event.price))")
                    .font(Theme.monoCaption())
                Text(event.date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, Theme.s8)
    }

    private var feedRowSkeleton: some View {
        HStack(spacing: Theme.s12) {
            skeletonRect(width: 4, height: 36).cornerRadius(3)
            skeletonRect(width: 28, height: 28).cornerRadius(Theme.radiusS)
            VStack(alignment: .leading, spacing: 4) {
                skeletonRect(width: 80, height: 12).cornerRadius(3)
                skeletonRect(width: 120, height: 10).cornerRadius(3)
            }
            Spacer()
            skeletonRect(width: 50, height: 12).cornerRadius(3)
        }
        .padding(.vertical, Theme.s8)
        .shimmering()
    }

    // MARK: - Research card

    @ViewBuilder
    private var researchCard: some View {
        let summary = quantStatus.status?.researchSummary
        // Only show research card when there's a summary — verdict already shown in goLiveCard
        if let summary {
            VStack(alignment: .leading, spacing: Theme.s12) {
                Label("Research Arc", systemImage: "flask.fill")
                    .font(.subheadline.bold())

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(researchExpanded ? nil : 3)
                    .animation(.easeInOut(duration: 0.2), value: researchExpanded)

                Button {
                    withAnimation { researchExpanded.toggle() }
                } label: {
                    Text(researchExpanded ? "Show less" : "Show more")
                        .font(.caption.bold())
                        .foregroundStyle(.ledgerAccent)
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.s16)
            .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
        }
    }

    // MARK: - Ask Claude button

    private var askClaudeButton: some View {
        Button {
            if !chatSeeded {
                chatVM.financialContext = buildBotContext()
                chatVM.messages = [ChatMessage(role: "assistant", text: buildOpeningMessage())]
                chatSeeded = true
            } else {
                chatVM.financialContext = buildBotContext()
            }
            showingChat = true
        } label: {
            HStack {
                if #available(iOS 17, *) {
                    Image(systemName: "sparkles")
                        .symbolEffect(.pulse, options: .repeating)
                } else {
                    Image(systemName: "sparkles")
                }
                Text("Ask Claude About Your Bots")
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold())
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(Theme.s16)
            .background(Color.ledgerAccent, in: RoundedRectangle(cornerRadius: Theme.radiusM))
            .shadow(color: Color.ledgerAccent.opacity(0.35), radius: 12, y: 4)
        }
        .buttonStyle(ScaleButtonStyle(pressedScale: 0.97))
    }

    // MARK: - Claude context builders

    private func buildBotContext() -> String {
        var lines = ["BOT SYSTEM STATUS (paper/simulated trading):"]
        if let status = quantStatus.status {
            lines.append("  Main equity: \(status.equityMain.map { $0.asCurrency(code: "USD") } ?? "—")")
            if let pnl = status.dailyPnlMain, let eq = status.equityMain {
                let prev = eq - pnl; let pct = prev > 0 ? (pnl / prev * 100) : 0
                lines.append("  Today's P&L: \(pnl >= 0 ? "+" : "")\(pnl.asCurrency(code: "USD")) (\(String(format: "%.2f", pct))%)")
            }
            if let stances = status.stances {
                lines.append("  Stances: \(stances.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", "))")
            }
            if let strategy = status.activeStrategy { lines.append("  Strategy: \(strategyLabel(strategy))") }
            if let verdict = status.forwardTestsVerdict { lines.append("  Forward test verdict: \(verdict)") }
            // Max drawdown context for Claude
            let curve = dataService.snapshot?.equityCurve ?? []
            if !curve.isEmpty {
                let dd = maxDrawdown(curve)
                lines.append("  Max drawdown: -\(String(format: "%.1f", dd * 100))%")
                if let bpct = btcBenchmarkReturn {
                    lines.append("  BTC \(selectedRange.rawValue) return: \(bpct >= 0 ? "+" : "")\(String(format: "%.1f", bpct))%")
                }
            }
        }
        if let snapshot = dataService.snapshot {
            lines.append("\nRECENT BOT ACTIVITY (last 5 events):")
            for event in snapshot.feed.prefix(5) {
                lines.append("  \(event.ts) \(event.ticker) \(event.action.uppercased()) @ $\(String(format: "%.2f", event.price))\(event.reason.map { " — \($0)" } ?? "")")
            }
            if let curve = snapshot.equityCurve.last {
                lines.append("  Latest equity point: $\(String(format: "%.2f", curve.equity)) at \(curve.t)")
            }
            let tradeCount = allDecisions.filter { $0.isSubmitted }.count
            if tradeCount > 0 { lines.append("  Total submitted orders: \(tradeCount)") }
        }
        return lines.joined(separator: "\n")
    }

    private func buildOpeningMessage() -> String {
        guard let status = quantStatus.status else {
            return "I can see your quant bots are active. What would you like to know about your trading system?"
        }
        let stanceStr: String
        if let stances = status.stances {
            let unique = Set(stances.values)
            stanceStr = unique.count == 1
                ? "all bots are \(unique.first!)"
                : stances.sorted { $0.key < $1.key }
                    .map { "\($0.key.components(separatedBy: "/").first ?? $0.key): \($0.value)" }
                    .joined(separator: ", ")
        } else {
            stanceStr = "stances unavailable"
        }
        let pnlStr = status.dailyPnlMain.map { pnl in
            " Daily P&L is \(pnl >= 0 ? "+" : "")\(pnl.asCurrency(code: "USD"))."
        } ?? ""
        return "I can see your BTC/ETH/SOL bots — \(stanceStr).\(pnlStr) What would you like to know — performance, a specific trade, or the research direction?"
    }

    // MARK: - Computed helpers

    private var allDecisions: [BotDecision] {
        dataService.snapshot?.coins.flatMap { $0.decisions } ?? []
    }

    private var candlesForRange: [OHLCCandle] {
        let all = dataService.candles[selectedSymbol] ?? []
        if selectedRange == .oneDay {
            let cutoff = Date().addingTimeInterval(-86400)
            return all.filter { $0.date >= cutoff }
        }
        return all
    }

    private var decisionsInRange: [BotDecision] {
        let all = dataService.snapshot?.coins.first(where: { $0.symbol == selectedSymbol })?.decisions ?? []
        let visible = candlesForRange
        guard let first = visible.first?.date, let last = visible.last?.date else { return all }
        return all.filter { $0.date >= first && $0.date <= last }
    }

    private var stanceCards: [(symbol: String, stance: String)] {
        (quantStatus.status?.stances ?? [:])
            .sorted { $0.key < $1.key }
            .map { (symbol: $0.key, stance: $0.value) }
    }

    private func strategyLabel(_ s: String) -> String {
        switch s.lowercased() {
        case "trend":     return "200-day trend"
        case "consensus": return "consensus"
        default:          return s
        }
    }

    private func stanceColor(_ stance: String) -> Color {
        switch stance.uppercased() {
        case "HOLDING", "LONG": return .ledgerPositive
        case "IN CASH", "FLAT": return .secondary
        case "EMERGENCY STOP":  return .ledgerNegative
        default:                return .secondary
        }
    }

    private func feedColor(_ event: FeedEvent) -> Color {
        if event.emergencyStop == true { return .ledgerNegative }
        switch event.action {
        case "submitted":                                         return .ledgerAccent
        case "error", "kill_switch", "hold_daily_loss_halt":     return .ledgerNegative
        case "cancelled", "rejected", "expired":                 return .secondary
        default:                                                  return .ledgerPositive
        }
    }

    private func feedIcon(_ event: FeedEvent) -> String {
        if event.emergencyStop == true { return "exclamationmark.triangle.fill" }
        switch event.action {
        case "submitted":                        return "arrow.up.arrow.down.circle.fill"
        case "error":                            return "xmark.circle.fill"
        case "cancelled", "rejected", "expired": return "minus.circle"
        default:                                 return "checkmark.circle.fill"
        }
    }

    private func refetchCandlesIfNeeded(days: Int) async {
        async let btc = dataService.fetchCandles(for: "BTC/USD", days: days)
        async let eth = dataService.fetchCandles(for: "ETH/USD", days: days)
        async let sol = dataService.fetchCandles(for: "SOL/USD", days: days)
        let (b, e, s) = await (btc, eth, sol)
        dataService.updateCandles(for: "BTC/USD", candles: b)
        dataService.updateCandles(for: "ETH/USD", candles: e)
        dataService.updateCandles(for: "SOL/USD", candles: s)
    }

    // MARK: - Max drawdown + benchmark helpers

    private func maxDrawdown(_ curve: [EquityPoint]) -> Double {
        var peak  = curve.first?.equity ?? 0
        var maxDD = 0.0
        for pt in curve {
            if pt.equity > peak { peak = pt.equity }
            if peak > 0 {
                let dd = (peak - pt.equity) / peak
                if dd > maxDD { maxDD = dd }
            }
        }
        return maxDD
    }

    /// BTC price return % for the currently selected range, using the loaded candle data.
    private var btcBenchmarkReturn: Double? {
        let candles = dataService.candles["BTC/USD"] ?? []
        guard let first = candles.first?.close,
              let last  = candles.last?.close,
              first > 0 else { return nil }
        return (last - first) / first * 100
    }

    // MARK: - Stats cell helper

    private func statsCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(.tertiary)
            Text(value).font(Theme.monoCaption().bold()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.s4)
    }

    // MARK: - Skeleton helpers

    private func skeletonRect(width: CGFloat?, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(.systemFill))
            .frame(width: width, height: height)
            .shimmering()
    }
}

#Preview {
    BotsView()
        .environmentObject(QuantStatusService())
}
