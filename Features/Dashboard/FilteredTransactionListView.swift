import SwiftUI

// General-purpose drillthrough view: takes a pre-filtered array of transactions.
// Used by Dashboard chart taps and "See All" links.
struct FilteredTransactionListView: View {
    let title:        String
    let transactions: [CDTransaction]

    @AppStorage("currencyCode") private var currencyCode = "USD"
    @State private var searchText = ""

    // MARK: - Date grouping (mirrors AccountDetailView)

    private enum Group: String, Hashable {
        case today     = "Today"
        case yesterday = "Yesterday"
        case thisWeek  = "This Week"
        case thisMonth = "This Month"
        case older     = "Older"
        static let ordered: [Group] = [.today, .yesterday, .thisWeek, .thisMonth, .older]
    }

    private func group(for date: Date?) -> Group {
        guard let date else { return .older }
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        let weekAgo = cal.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        if date >= weekAgo             { return .thisWeek }
        let now = Date()
        let sameMonth = cal.component(.year,  from: date) == cal.component(.year,  from: now)
                     && cal.component(.month, from: date) == cal.component(.month, from: now)
        return sameMonth ? .thisMonth : .older
    }

    private var filtered: [CDTransaction] {
        guard !searchText.isEmpty else { return transactions }
        let q = searchText.lowercased()
        return transactions.filter {
            $0.wrappedNotes.lowercased().contains(q)
                || $0.transactionCategory.displayName.lowercased().contains(q)
                || ($0.account?.wrappedName.lowercased().contains(q) ?? false)
        }
    }

    private var grouped: [(group: Group, txs: [CDTransaction])] {
        let sorted = filtered.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        var buckets: [Group: [CDTransaction]] = [:]
        for tx in sorted { buckets[group(for: tx.date), default: []].append(tx) }
        return Group.ordered.compactMap { g in
            guard let txs = buckets[g], !txs.isEmpty else { return nil }
            return (group: g, txs: txs)
        }
    }

    private var totalExpenses: Double {
        filtered.filter { $0.amount < 0 }.reduce(0) { $0 + abs($1.amount) }
    }
    private var totalIncome: Double {
        filtered.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        List {
            // Summary header
            if !transactions.isEmpty {
                Section {
                    HStack(spacing: 0) {
                        summaryPill(label: "Income",   value: totalIncome,   color: .ledgerPositive)
                        Divider().frame(height: 36)
                        summaryPill(label: "Expenses", value: totalExpenses, color: .ledgerNegative)
                        Divider().frame(height: 36)
                        summaryPill(label: "Net",      value: totalIncome - totalExpenses,
                                    color: .changeColor(for: totalIncome - totalExpenses))
                    }
                    .padding(.vertical, 6)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            if filtered.isEmpty && !searchText.isEmpty {
                if #available(iOS 17, *) {
                    ContentUnavailableView.search(text: searchText)
                }
            } else if transactions.isEmpty {
                if #available(iOS 17, *) {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "tray",
                        description: Text("No transactions match this filter.")
                    )
                }
            } else {
                ForEach(grouped, id: \.group) { item in
                    Section(item.group.rawValue) {
                        ForEach(item.txs) { tx in
                            DrillTransactionRow(tx: tx, currencyCode: currencyCode)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search transactions…")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }

    private func summaryPill(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value.asCurrency(code: currencyCode))
                .font(Theme.monoCaption().bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Row

private struct DrillTransactionRow: View {
    let tx:           CDTransaction
    let currencyCode: String

    var body: some View {
        HStack(spacing: Theme.s12) {
            Image(systemName: tx.transactionCategory.icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusS))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let acct = tx.account?.wrappedName {
                        Text(acct).font(.caption2).foregroundStyle(.secondary)
                        Text("·").font(.caption2).foregroundStyle(.tertiary)
                    }
                    if let date = tx.date {
                        Text(date, style: .date).font(.caption2).foregroundStyle(.secondary)
                    }
                    if tx.isSplit {
                        Text("· split").font(.caption2).foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            Text(tx.amount.asCurrency(code: currencyCode))
                .font(Theme.monoCaption())
                .foregroundStyle(color)
        }
        .padding(.vertical, Theme.s4)
    }

    private var title: String {
        tx.wrappedNotes.isEmpty ? tx.transactionCategory.displayName : tx.wrappedNotes
    }
    private var color: Color { tx.isExpense ? .ledgerNegative : .ledgerPositive }
}
