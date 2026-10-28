import SwiftUI
import Charts

struct CashFlowForecastView: View {
    let recurringRules:  [RecurringTransaction]
    let currentBalance:  Double
    let currencyCode:    String

    @State private var horizon: Int = 90   // days to project

    // MARK: - Projection engine

    private struct ForecastEvent: Identifiable {
        let id   = UUID()
        let date: Date
        let name: String
        let amount: Double
        var isIncome: Bool { amount > 0 }
    }

    private struct ForecastPoint: Identifiable {
        var id: Date { date }
        let date:    Date
        let balance: Double
    }

    private var events: [ForecastEvent] {
        let cal    = Calendar.current
        let today  = cal.startOfDay(for: .now)
        guard let end = cal.date(byAdding: .day, value: horizon, to: today) else { return [] }

        var result: [ForecastEvent] = []
        for rule in recurringRules {
            var next = rule.nextDueDate ?? .distantFuture
            while next <= end {
                if next >= today {
                    result.append(ForecastEvent(
                        date:   next,
                        name:   rule.name ?? rule.transactionCategory.displayName,
                        amount: rule.amount
                    ))
                }
                let advanced = rule.recurringFrequency.nextDate(after: next)
                guard advanced > next else { break }
                next = advanced
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    private var forecastPoints: [ForecastPoint] {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let end = cal.date(byAdding: .day, value: horizon, to: today) else { return [] }

        // Group events by day for the running sum.
        var eventsByDay: [Date: Double] = [:]
        for ev in events {
            let day = cal.startOfDay(for: ev.date)
            eventsByDay[day, default: 0] += ev.amount
        }

        var running = currentBalance
        var points  = [ForecastPoint]()
        var day     = today
        while day <= end {
            running += eventsByDay[day] ?? 0
            points.append(ForecastPoint(date: day, balance: running))
            day = cal.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return points
    }

    // Group events by calendar month for the list.
    private var groupedEvents: [(month: String, events: [ForecastEvent])] {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        var groups: [String: [ForecastEvent]] = [:]
        var order:  [String] = []
        for ev in events {
            let key = fmt.string(from: ev.date)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(ev)
        }
        return order.map { (month: $0, events: groups[$0]!) }
    }

    // Totals over the full horizon.
    private var totalIn:  Double { events.filter { $0.isIncome }.reduce(0) { $0 + $1.amount } }
    private var totalOut: Double { events.filter { !$0.isIncome }.reduce(0) { $0 + abs($1.amount) } }
    private var netFlow:  Double { totalIn - totalOut }

    // MARK: - Body

    var body: some View {
        List {
            // MARK: Horizon picker
            Section {
                Picker("Horizon", selection: $horizon) {
                    Text("30 days").tag(30)
                    Text("60 days").tag(60)
                    Text("90 days").tag(90)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            // MARK: Balance chart
            Section {
                if forecastPoints.isEmpty {
                    Label("No recurring transactions set up yet.",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    let minBal = forecastPoints.map(\.balance).min() ?? 0
                    let maxBal = forecastPoints.map(\.balance).max() ?? 1
                    let pad    = max((maxBal - minBal) * 0.12, 50)
                    let isPos  = netFlow >= 0

                    Chart(forecastPoints) { pt in
                        LineMark(x: .value("Date", pt.date), y: .value("Balance", pt.balance))
                            .foregroundStyle(isPos ? Color.ledgerPositive : Color.ledgerNegative)
                            .interpolationMethod(.stepEnd)
                        AreaMark(x: .value("Date", pt.date), y: .value("Balance", pt.balance))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [(isPos ? Color.ledgerPositive : Color.ledgerNegative).opacity(0.2), .clear],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.stepEnd)
                    }
                    .chartYScale(domain: (minBal - pad) ... (maxBal + pad))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .font(.caption2).foregroundStyle(.secondary)
                            AxisGridLine().foregroundStyle(Color(.separator).opacity(0.5))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine().foregroundStyle(Color(.separator).opacity(0.5))
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(compactCurrency(v, code: currencyCode))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(height: 160)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
            }

            // MARK: Net summary row
            Section {
                HStack(spacing: 0) {
                    summaryCell(label: "In",  value: totalIn,  color: .ledgerPositive)
                    Divider().frame(height: 40)
                    summaryCell(label: "Out", value: totalOut, color: .ledgerNegative)
                    Divider().frame(height: 40)
                    summaryCell(label: "Net", value: netFlow,  color: Color.changeColor(for: netFlow))
                }
                .listRowInsets(EdgeInsets())
            }

            // MARK: Event list
            ForEach(groupedEvents, id: \.month) { group in
                Section(group.month) {
                    ForEach(group.events) { ev in
                        HStack {
                            Image(systemName: ev.isIncome ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .foregroundStyle(ev.isIncome ? .ledgerPositive : .ledgerNegative)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ev.name)
                                    .font(.subheadline)
                                Text(ev.date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(ev.amount.asCurrency(code: currencyCode))
                                .font(Theme.monoSubhead())
                                .foregroundStyle(ev.isIncome ? .ledgerPositive : .ledgerNegative)
                        }
                    }
                }
            }

            if groupedEvents.isEmpty && !recurringRules.isEmpty {
                Section {
                    Text("No events in the next \(horizon) days.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Cash Flow Forecast")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summaryCell(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(abs(value).asCurrency(code: currencyCode))
                .font(Theme.monoCaption().bold()).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.s8)
    }

    private func compactCurrency(_ value: Double, code: String) -> String {
        let abs = Swift.abs(value)
        let sign = value < 0 ? "-" : ""
        let sym: String = {
            let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = code
            return f.currencySymbol ?? "$"
        }()
        switch abs {
        case 1_000_000...: return "\(sign)\(sym)\(String(format: "%.1f", abs / 1_000_000))M"
        case 1_000...:     return "\(sign)\(sym)\(String(format: "%.0f", abs / 1_000))k"
        default:           return "\(sign)\(sym)\(String(format: "%.0f", abs))"
        }
    }
}

#Preview {
    NavigationStack {
        CashFlowForecastView(recurringRules: [], currentBalance: 12_450, currencyCode: "USD")
    }
}
