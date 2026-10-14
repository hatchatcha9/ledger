import SwiftUI
import CoreData

struct JournalView: View {
    @Environment(\.managedObjectContext) private var ctx

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.entryDate, order: .reverse)],
        animation: .default
    ) private var entries: FetchedResults<JournalEntry>

    @State private var showingAddSheet   = false
    @State private var editingEntry: JournalEntry? = nil
    @State private var searchText        = ""
    @State private var outcomeFilter: TradeOutcome? = nil   // nil = All
    @State private var showTaxSummary    = false

    private var filteredEntries: [JournalEntry] {
        entries.filter { entry in
            if let f = outcomeFilter, entry.tradeOutcome != f { return false }
            guard !searchText.isEmpty else { return true }
            let q = searchText.lowercased()
            return entry.wrappedSymbol.lowercased().contains(q)
                || entry.wrappedStrategyTag.lowercased().contains(q)
                || entry.wrappedNotes.lowercased().contains(q)
        }
    }

    // MARK: - Performance stats

    private var closedEntries: [JournalEntry] {
        entries.filter { !$0.isOpen }
    }

    private var winRate: Double? {
        let closed = closedEntries
        guard !closed.isEmpty else { return nil }
        let wins = closed.filter { ($0.realisedPnL ?? 0) > 0 }.count
        return Double(wins) / Double(closed.count) * 100
    }

    private var totalPnL: Double {
        entries.compactMap(\.realisedPnL).reduce(0, +)
    }

    private var avgPnL: Double? {
        let pnls = entries.compactMap(\.realisedPnL)
        guard !pnls.isEmpty else { return nil }
        return pnls.reduce(0, +) / Double(pnls.count)
    }

    private var openCount: Int { entries.filter { $0.isOpen }.count }

    // Group closed entries by calendar year for tax P&L summary.
    private var taxYearPnL: [(year: Int, pnl: Double, count: Int)] {
        let cal = Calendar.current
        var buckets = [Int: (Double, Int)]()
        for e in closedEntries {
            guard let pnl = e.realisedPnL else { continue }
            let year = cal.component(.year, from: e.exitDate ?? e.entryDate ?? .now)
            let (prev, count) = buckets[year, default: (0, 0)]
            buckets[year] = (prev + pnl, count + 1)
        }
        return buckets
            .map { (year: $0.key, pnl: $0.value.0, count: $0.value.1) }
            .sorted { $0.year > $1.year }
    }

    var body: some View {
        NavigationStack {
            List {
                if !entries.isEmpty {
                    Section {
                        statsCard
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }

                    // Tax year summary
                    if !taxYearPnL.isEmpty {
                        Section {
                            DisclosureGroup(isExpanded: $showTaxSummary) {
                                ForEach(taxYearPnL, id: \.year) { row in
                                    HStack {
                                        Text("Tax Year \(row.year)")
                                            .font(.subheadline)
                                        Text("(\(row.count) trades)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text((row.pnl >= 0 ? "+" : "") + row.pnl.asCurrency())
                                            .font(Theme.monoBody().bold())
                                            .foregroundStyle(Color.changeColor(for: row.pnl))
                                    }
                                }
                            } label: {
                                Label("Realized P&L by Tax Year", systemImage: "doc.text.magnifyingglass")
                                    .font(.subheadline.bold())
                            }
                        }
                    }
                }
                ForEach(filteredEntries) { entry in
                    JournalRow(entry: entry)
                        .contentShape(Rectangle())
                        .onTapGesture { editingEntry = entry }
                }
                .onDelete(perform: deleteEntries)
            }
            .searchable(text: $searchText, prompt: "Symbol, strategy, notes…")
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    filterMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddEditJournalEntryView()
                    .environment(\.managedObjectContext, ctx)
            }
            .sheet(item: $editingEntry) { entry in
                AddEditJournalEntryView(entry: entry)
                    .environment(\.managedObjectContext, ctx)
            }
            .overlay {
                if entries.isEmpty {
                    if #available(iOS 17, *) {
                        ContentUnavailableView {
                            Label("No Entries", systemImage: "book.closed")
                        } description: {
                            Text("Log your trades to track patterns and build your edge.")
                        } actions: {
                            Button("Log First Trade") { showingAddSheet = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else if filteredEntries.isEmpty {
                    if !searchText.isEmpty {
                        if #available(iOS 17, *) {
                            ContentUnavailableView.search(text: searchText)
                        }
                    } else if let filter = outcomeFilter {
                        if #available(iOS 17, *) {
                            ContentUnavailableView(
                                "No \(filter.displayName) Trades",
                                systemImage: filter.icon,
                                description: Text("No journal entries match this filter.")
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Stats card

    private var statsCard: some View {
        HStack(spacing: 0) {
            statPill(
                value: winRate.map { "\(String(format: "%.0f", $0))%" } ?? "—",
                label: "Win Rate",
                color: winRate.map { $0 >= 50 ? Color.ledgerPositive : Color.ledgerNegative } ?? Color.secondary
            )
            statDivider
            statPill(
                value: totalPnL == 0 ? "—" : (totalPnL >= 0 ? "+" : "") + totalPnL.asCurrency(),
                label: "Total P&L",
                color: Color.changeColor(for: totalPnL)
            )
            statDivider
            statPill(
                value: avgPnL.map { ($0 >= 0 ? "+" : "") + $0.asCurrency() } ?? "—",
                label: "Avg P&L",
                color: avgPnL.map { Color.changeColor(for: $0) } ?? .secondary
            )
            statDivider
            statPill(
                value: "\(openCount)",
                label: "Open",
                color: .ledgerAccent
            )
        }
        .padding(.vertical, Theme.s12)
        .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
        .padding(.horizontal, Theme.s16)
        .padding(.vertical, Theme.s4)
    }

    private func statPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Theme.monoSubhead().bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Divider()
            .frame(height: 32)
    }

    // MARK: - Filter menu

    @ViewBuilder
    private var filterMenu: some View {
        Menu {
            Button {
                HapticService.select()
                outcomeFilter = nil
            } label: {
                Label("All Outcomes", systemImage: outcomeFilter == nil ? "checkmark" : "line.3.horizontal.decrease")
            }
            Divider()
            ForEach(TradeOutcome.allCases) { outcome in
                Button {
                    HapticService.select()
                    outcomeFilter = outcomeFilter == outcome ? nil : outcome
                } label: {
                    Label(outcome.displayName,
                          systemImage: outcomeFilter == outcome ? "checkmark" : outcome.icon)
                }
            }
        } label: {
            Image(systemName: outcomeFilter == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
    }

    // MARK: - Actions

    private func deleteEntries(at offsets: IndexSet) {
        HapticService.impact(.rigid)
        offsets.map { filteredEntries[$0] }.forEach(ctx.delete)
        try? ctx.save()
    }
}

// MARK: - Journal Row

private struct JournalRow: View {
    @ObservedObject var entry: JournalEntry

    var body: some View {
        HStack(spacing: Theme.s12) {
            // Direction badge
            directionBadge

            VStack(alignment: .leading, spacing: 3) {
                // Symbol + outcome badge
                HStack {
                    Text(entry.wrappedSymbol)
                        .font(.body.bold())
                    Spacer()
                    OutcomeBadge(outcome: entry.tradeOutcome)
                }

                // Conviction + date
                HStack {
                    Text(entry.convictionStars)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let date = entry.entryDate {
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Strategy tag, if set
                if !entry.wrappedStrategyTag.isEmpty {
                    Text(entry.wrappedStrategyTag)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Realised P&L, if closed
                if let pnl = entry.realisedPnL {
                    Text(pnl >= 0 ? "+\(pnl.asCurrency())" : pnl.asCurrency())
                        .font(Theme.monoBody().bold())
                        .foregroundStyle(pnl >= 0 ? .ledgerPositive : .ledgerNegative)
                }
            }
        }
        .padding(.vertical, Theme.s4)
    }

    private var directionBadge: some View {
        Text(entry.tradeDirection == .long ? "L" : "S")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(
                entry.tradeDirection == .long ? Color.ledgerPositive : Color.ledgerNegative,
                in: RoundedRectangle(cornerRadius: Theme.radiusS)
            )
    }
}

// MARK: - Outcome Badge

private struct OutcomeBadge: View {
    let outcome: TradeOutcome

    var body: some View {
        Text(outcome.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(outcome.color.opacity(0.15), in: Capsule())
            .foregroundStyle(outcome.color)
    }
}

#Preview {
    JournalView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
}
