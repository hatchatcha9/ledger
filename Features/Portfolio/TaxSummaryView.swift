import SwiftUI

struct TaxSummaryView: View {
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.exitDate, order: .reverse)],
        predicate: NSPredicate(format: "outcome != %@", "open"),
        animation: .default
    ) private var closedTrades: FetchedResults<JournalEntry>

    @AppStorage("currencyCode")    private var currencyCode = "USD"
    @AppStorage("taxRateShort")    private var taxRateShort: Double = 25
    @AppStorage("taxRateLong")     private var taxRateLong:  Double = 15

    @State private var selectedYear: Int = Calendar.current.component(.year, from: .now)

    private var availableYears: [Int] {
        let years = closedTrades.compactMap { entry -> Int? in
            guard let d = entry.exitDate else { return nil }
            return Calendar.current.component(.year, from: d)
        }
        let unique = Array(Set(years)).sorted(by: >)
        let current = Calendar.current.component(.year, from: .now)
        return unique.contains(current) ? unique : [current] + unique
    }

    private struct TaxableTrade {
        let symbol:    String
        let pnl:       Double
        let isLong:    Bool   // true = held 365+ days
        let exitDate:  Date
    }

    private var tradesForYear: [TaxableTrade] {
        let cal = Calendar.current
        return closedTrades.compactMap { entry -> TaxableTrade? in
            guard let exitDate  = entry.exitDate,
                  let pnl       = entry.realisedPnL,
                  cal.component(.year, from: exitDate) == selectedYear
            else { return nil }

            let held = cal.dateComponents([.day], from: entry.entryDate, to: exitDate).day ?? 0
            return TaxableTrade(
                symbol:   entry.wrappedSymbol,
                pnl:      pnl,
                isLong:   held >= 365,
                exitDate: exitDate
            )
        }
    }

    private var shortTermGains: Double { tradesForYear.filter { !$0.isLong && $0.pnl > 0 }.reduce(0) { $0 + $1.pnl } }
    private var shortTermLosses: Double { tradesForYear.filter { !$0.isLong && $0.pnl < 0 }.reduce(0) { $0 + $1.pnl } }
    private var longTermGains:  Double { tradesForYear.filter { $0.isLong  && $0.pnl > 0 }.reduce(0) { $0 + $1.pnl } }
    private var longTermLosses: Double { tradesForYear.filter { $0.isLong  && $0.pnl < 0 }.reduce(0) { $0 + $1.pnl } }
    private var netShortTerm:   Double { shortTermGains + shortTermLosses }
    private var netLongTerm:    Double { longTermGains  + longTermLosses }
    private var netTotal:       Double { netShortTerm + netLongTerm }
    private var estimatedTax:   Double {
        max(0, netShortTerm) * (taxRateShort / 100) + max(0, netLongTerm) * (taxRateLong / 100)
    }

    // Quarterly breakdown
    private func pnlForQuarter(_ q: Int) -> Double {
        let cal = Calendar.current
        return tradesForYear
            .filter { ((cal.component(.month, from: $0.exitDate) - 1) / 3) + 1 == q }
            .reduce(0) { $0 + $1.pnl }
    }

    var body: some View {
        Form {
            // MARK: Year picker
            Section {
                Picker("Tax Year", selection: $selectedYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            // MARK: Summary tiles
            if tradesForYear.isEmpty {
                Section {
                    Label("No closed trades in \(selectedYear).", systemImage: "doc.text.magnifyingglass")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            } else {
                Section("Net Realized P&L") {
                    taxRow(label: "Short-Term Gains", value: shortTermGains, color: .ledgerPositive)
                    taxRow(label: "Short-Term Losses", value: shortTermLosses, color: .ledgerNegative)
                    Divider()
                    taxRow(label: "Net Short-Term", value: netShortTerm,
                           color: Color.changeColor(for: netShortTerm), bold: true)

                    taxRow(label: "Long-Term Gains", value: longTermGains, color: .ledgerPositive)
                    taxRow(label: "Long-Term Losses", value: longTermLosses, color: .ledgerNegative)
                    Divider()
                    taxRow(label: "Net Long-Term", value: netLongTerm,
                           color: Color.changeColor(for: netLongTerm), bold: true)

                    taxRow(label: "Net Total", value: netTotal,
                           color: Color.changeColor(for: netTotal), bold: true)
                }

                // MARK: Estimated tax
                Section {
                    taxRow(label: "Est. Short-Term Tax (\(Int(taxRateShort))%)",
                           value: max(0, netShortTerm) * (taxRateShort / 100),
                           color: .ledgerNegative)
                    taxRow(label: "Est. Long-Term Tax (\(Int(taxRateLong))%)",
                           value: max(0, netLongTerm) * (taxRateLong / 100),
                           color: .ledgerNegative)
                    HStack {
                        Text("Total Estimated Tax")
                            .font(.subheadline.bold())
                        Spacer()
                        Text(estimatedTax.asCurrency(code: currencyCode))
                            .font(Theme.monoSubhead().bold())
                            .foregroundStyle(.ledgerNegative)
                    }
                } header: {
                    Text("Estimated Tax")
                } footer: {
                    Text("Informational only — consult a tax professional. Set your rates below.")
                }

                // MARK: Quarterly breakdown
                Section("Quarterly Breakdown") {
                    ForEach(1...4, id: \.self) { q in
                        let pnl = pnlForQuarter(q)
                        HStack {
                            Text("Q\(q) \(selectedYear)")
                                .font(.subheadline)
                            Spacer()
                            Text((pnl >= 0 ? "+" : "") + pnl.asCurrency(code: currencyCode))
                                .font(Theme.monoSubhead())
                                .foregroundStyle(Color.changeColor(for: pnl))
                        }
                    }
                }

                // MARK: Trade list
                Section("Trades") {
                    ForEach(Array(tradesForYear.enumerated()), id: \.offset) { _, trade in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: Theme.s4) {
                                    Text(trade.symbol)
                                        .font(.subheadline.bold())
                                    Text(trade.isLong ? "Long-Term" : "Short-Term")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(trade.isLong ? Color.ledgerPositive.opacity(0.1) : Color.orange.opacity(0.1),
                                                    in: Capsule())
                                        .foregroundStyle(trade.isLong ? .ledgerPositive : .orange)
                                }
                                Text(trade.exitDate, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text((trade.pnl >= 0 ? "+" : "") + trade.pnl.asCurrency(code: currencyCode))
                                .font(Theme.monoSubhead())
                                .foregroundStyle(Color.changeColor(for: trade.pnl))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // MARK: Tax rate settings
            Section("Tax Rates") {
                HStack {
                    Text("Short-Term Rate")
                    Spacer()
                    Text("\(Int(taxRateShort))%")
                        .font(Theme.monoBody())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $taxRateShort, in: 0...50, step: 1)
                    .tint(Color.orange)

                HStack {
                    Text("Long-Term Rate")
                    Spacer()
                    Text("\(Int(taxRateLong))%")
                        .font(Theme.monoBody())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $taxRateLong, in: 0...40, step: 1)
                    .tint(Color.ledgerAccent)
            }
        }
        .navigationTitle("Tax Summary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func taxRow(label: String, value: Double, color: Color, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(bold ? .subheadline.bold() : .subheadline)
            Spacer()
            Text(value.asCurrency(code: currencyCode))
                .font(bold ? Theme.monoSubhead().bold() : Theme.monoSubhead())
                .foregroundStyle(color)
        }
    }
}

#Preview {
    NavigationStack { TaxSummaryView() }
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
