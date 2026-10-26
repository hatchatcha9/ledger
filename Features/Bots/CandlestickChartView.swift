import SwiftUI
import Charts

// MARK: - Time range

enum CandleRange: String, CaseIterable {
    case oneDay    = "1D"
    case sevenDays = "7D"
    case month     = "30D"

    var days: Int {
        switch self {
        case .oneDay:    return 1
        case .sevenDays: return 7
        case .month:     return 30
        }
    }
}

// MARK: - Candlestick chart (iOS 16+)
// RectangleMark is available from iOS 16.0 (Swift Charts launch), same as LineMark/AreaMark.
// No @available gate needed here — the whole Charts import is already at the app's minimum target.

struct CandlestickChartView: View {
    let candles:      [OHLCCandle]
    let decisions:    [BotDecision]
    let symbol:       String
    let range:        CandleRange
    var currentPrice: Double? = nil   // last close for current-price rule mark

    @State private var popoverDecision: BotDecision?
    @State private var selectedCandle:  OHLCCandle?

    private var submitted: [BotDecision] { decisions.filter { $0.isSubmitted } }

    // Tap tolerance scales with candle granularity: ~2 candles worth of time
    private var tapToleranceSeconds: TimeInterval {
        switch range {
        case .oneDay:    return 3600 * 2      // 1D has ~30m candles: 2-candle window = 1h
        case .sevenDays: return 3600 * 8      // 7D has ~4h candles: 2-candle window = 8h
        case .month:     return 3600 * 36     // 30D has ~1.5d candles: 2-candle window = 36h
        }
    }

    var body: some View {
        VStack(spacing: Theme.s8) {
            if candles.isEmpty {
                emptyState
            } else {
                chart
                ohlcInfoBar
            }
        }
        .onChange(of: symbol) { _ in selectedCandle = nil; popoverDecision = nil }
        .onChange(of: range)  { _ in selectedCandle = nil; popoverDecision = nil }
    }

    // MARK: - OHLC info bar (appears when a candle is tapped)

    @ViewBuilder
    private var ohlcInfoBar: some View {
        if selectedCandle == nil && popoverDecision == nil {
            Text("Tap chart for OHLC · Tap a marker for trade detail")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else if let candle = selectedCandle {
            HStack(spacing: Theme.s16) {
                VStack(spacing: 1) {
                    Text("O").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text(compactPrice(candle.open)).font(.system(size: 11, design: .monospaced))
                }
                VStack(spacing: 1) {
                    Text("H").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text(compactPrice(candle.high))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.ledgerPositive)
                }
                VStack(spacing: 1) {
                    Text("L").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text(compactPrice(candle.low))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.ledgerNegative)
                }
                VStack(spacing: 1) {
                    Text("C").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text(compactPrice(candle.close))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(candle.isBullish ? Color.ledgerPositive : Color.ledgerNegative)
                }
                Spacer()
                Text(candle.date, format: range == .oneDay
                     ? .dateTime.hour().minute()
                     : .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.s4)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: selectedCandle?.id)
        }
    }

    // MARK: - Main chart

    private var chart: some View {
        Chart {
            // Wicks
            ForEach(candles) { candle in
                RuleMark(
                    x:      .value("Time", candle.date),
                    yStart: .value("Low",  candle.low),
                    yEnd:   .value("High", candle.high)
                )
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(candle.isBullish ? Color.ledgerPositive : Color.ledgerNegative)
            }

            // Bodies
            ForEach(candles) { candle in
                RectangleMark(
                    x:      .value("Time",  candle.date),
                    yStart: .value("Open",  min(candle.open, candle.close)),
                    yEnd:   .value("Close", max(candle.open, candle.close)),
                    width:  candleWidth
                )
                .foregroundStyle(candle.isBullish ? Color.ledgerPositive : Color.ledgerNegative)
            }

            // Current price line
            if let price = currentPrice {
                RuleMark(y: .value("Current", price))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.ledgerAccent.opacity(0.7))
                    .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                        Text(price >= 1000
                             ? "$\(String(format: "%.0f", price))"
                             : "$\(String(format: "%.2f", price))")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.ledgerAccent)
                    }
            }

            // Bot decision markers — submitted orders only
            ForEach(submitted) { decision in
                PointMark(
                    x: .value("Time",  decision.date),
                    y: .value("Price", decision.price)
                )
                .symbolSize(200)
                .symbol {
                    ZStack {
                        Circle()
                            .fill(decision.isBuy ? Color.ledgerPositive : Color.ledgerNegative)
                            .frame(width: 14, height: 14)
                        Image(systemName: decision.isBuy
                              ? "arrowtriangle.up.fill"
                              : "arrowtriangle.down.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .annotation(position: decision.isBuy ? .bottom : .top, spacing: 2) {
                    if decision.id == popoverDecision?.id {
                        decisionPopover(decision)
                    }
                }
            }
        }
        .frame(height: 220)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Color(.separator).opacity(0.3))
                AxisValueLabel(format: range == .oneDay
                    ? .dateTime.hour()
                    : .dateTime.month(.abbreviated).day()
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Color(.separator).opacity(0.3))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(compactPrice(v))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let x = location.x - geo[proxy.plotAreaFrame].origin.x
                        guard let tapped = proxy.value(atX: x, as: Date.self) else { return }

                        // Check for nearby bot decision first
                        let nearestDecision = submitted.min(by: {
                            abs($0.date.timeIntervalSince(tapped)) <
                            abs($1.date.timeIntervalSince(tapped))
                        })
                        if let d = nearestDecision, abs(d.date.timeIntervalSince(tapped)) < tapToleranceSeconds {
                            popoverDecision = (popoverDecision?.id == d.id) ? nil : d
                            selectedCandle  = nil
                        } else {
                            // Fall back to nearest candle OHLC
                            popoverDecision = nil
                            let nearestCandle = candles.min(by: {
                                abs($0.date.timeIntervalSince(tapped)) <
                                abs($1.date.timeIntervalSince(tapped))
                            })
                            selectedCandle = (selectedCandle?.id == nearestCandle?.id) ? nil : nearestCandle
                        }
                    }
            }
        }
    }

    // MARK: - Decision popover

    private func decisionPopover(_ decision: BotDecision) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(decision.action.capitalized)
                .font(.caption2.bold())
                .foregroundStyle(decision.isBuy ? Color.ledgerPositive : Color.ledgerNegative)
            Text("$\(String(format: "%.2f", decision.price))")
                .font(.system(size: 10, design: .monospaced))
            if let reason = decision.reason {
                Text(reason)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: 160)
            }
        }
        .padding(Theme.s8)
        .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusS))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: Theme.s8) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.largeTitle)
                    .foregroundStyle(.quaternary)
                Text("No price data — check connection")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }
            Spacer()
        }
        .frame(height: 220)
    }

    // MARK: - Helpers

    private var candleWidth: MarkDimension {
        switch range {
        case .oneDay:    return .fixed(6)
        case .sevenDays: return .fixed(4)
        case .month:     return .fixed(2)
        }
    }

    private func compactPrice(_ value: Double) -> String {
        value >= 1000
            ? "$\(String(format: "%.0f", value))"
            : "$\(String(format: "%.2f", value))"
    }
}
