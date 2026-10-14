import SwiftUI
import CoreData

struct AccountDetailView: View {
    @Environment(\.managedObjectContext) private var ctx

    // NSManagedObject is an ObservableObject — SwiftUI re-renders when any
    // @NSManaged property changes, so we get live balance updates for free.
    @ObservedObject var account: Account

    @State private var showingAddTransaction   = false
    @State private var showingEditAccount      = false
    @State private var showingAddAsset         = false
    @State private var showingAddRecurring     = false
    @State private var editingTransaction: CDTransaction?      = nil
    @State private var editingAsset: Asset?                    = nil
    @State private var editingRecurring: RecurringTransaction? = nil
    @State private var showingDeleteConfirm    = false
    @State private var showingCSVImport        = false
    @State private var transactionSearch       = ""
    @State private var detectedPatterns: [DetectedPattern] = []
    @State private var showingDebtPayoff       = false
    @Environment(\.dismiss) private var dismiss

    private var filteredTransactions: [CDTransaction] {
        guard !transactionSearch.isEmpty else { return account.transactionsArray }
        let q = transactionSearch.lowercased()
        return account.transactionsArray.filter {
            $0.wrappedNotes.lowercased().contains(q)
                || $0.transactionCategory.displayName.lowercased().contains(q)
        }
    }

    // MARK: - Date grouping

    private enum TxDateGroup: String, Hashable {
        case today     = "Today"
        case yesterday = "Yesterday"
        case thisWeek  = "This Week"
        case thisMonth = "This Month"
        case older     = "Older"
        static let ordered: [TxDateGroup] = [.today, .yesterday, .thisWeek, .thisMonth, .older]
    }

    private func txDateGroup(for date: Date?) -> TxDateGroup {
        guard let date else { return .older }
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        let weekAgo = cal.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        if date >= weekAgo             { return .thisWeek }
        let now = Date()
        let sameMonth = cal.component(.year,  from: date) == cal.component(.year,  from: now)
                     && cal.component(.month, from: date) == cal.component(.month, from: now)
        if sameMonth                   { return .thisMonth }
        return .older
    }

    private var groupedFilteredTransactions: [(group: TxDateGroup, txs: [CDTransaction])] {
        var buckets: [TxDateGroup: [CDTransaction]] = [:]
        for tx in filteredTransactions {
            let g = txDateGroup(for: tx.date)
            buckets[g, default: []].append(tx)
        }
        return TxDateGroup.ordered.compactMap { group in
            guard let txs = buckets[group], !txs.isEmpty else { return nil }
            return (group: group, txs: txs)
        }
    }

    var body: some View {
        List {
            // MARK: Balance header
            Section {
                VStack(spacing: 6) {
                    Text(account.balance.asCurrency(code: account.wrappedCurrency))
                        .font(Theme.monoLargeTitle())
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: account.balance)
                    Text("Current Balance")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 24) {
                        statPill(label: "Transactions", value: "\(account.transactionsArray.count)")
                        statPill(label: "Assets", value: "\(account.assetsArray.count)")
                    }
                    .padding(.top, 4)

                    if account.accountType.isDebt {
                        Button {
                            showingDebtPayoff = true
                        } label: {
                            Label("Debt Payoff Planner", systemImage: "calendar.badge.minus")
                                .font(.subheadline)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.ledgerNegative)
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }

            // MARK: Assets
            Section {
                if account.assetsArray.isEmpty {
                    emptyAssetsRow
                } else {
                    ForEach(account.assetsArray) { asset in
                        AssetDetailRow(asset: asset)
                            .contentShape(Rectangle())
                            .onTapGesture { editingAsset = asset }
                    }
                    .onDelete(perform: deleteAssets)
                }
            } header: {
                HStack {
                    Text("Assets")
                    Spacer()
                    Button {
                        showingAddAsset = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.ledgerAccent)
                    }
                    .buttonStyle(.plain)
                }
            }

            // MARK: Auto-detected recurring patterns
            if !detectedPatterns.isEmpty {
                Section {
                    ForEach(detectedPatterns) { pattern in
                        Button {
                            createRecurringFromPattern(pattern)
                        } label: {
                            HStack(spacing: Theme.s12) {
                                Image(systemName: "wand.and.stars")
                                    .font(.body)
                                    .foregroundStyle(Color.ledgerAccent)
                                    .frame(width: 36, height: 36)
                                    .background(Color.ledgerAccent.opacity(0.1),
                                                in: RoundedRectangle(cornerRadius: Theme.radiusS))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pattern.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Text("\(pattern.frequency.displayName) · \(pattern.amount.asCurrency())")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("Add")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.ledgerAccent)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Label("Detected Patterns", systemImage: "wand.and.stars")
                        .foregroundStyle(Color.ledgerAccent)
                } footer: {
                    Text("Tap to add as a recurring transaction.")
                        .font(.caption)
                }
            }

            // MARK: Recurring
            Section {
                if account.recurringTransactionsArray.isEmpty {
                    emptyRecurringRow
                } else {
                    ForEach(account.recurringTransactionsArray) { r in
                        RecurringRow(recurring: r)
                            .contentShape(Rectangle())
                            .onTapGesture { editingRecurring = r }
                    }
                    .onDelete(perform: deleteRecurring)
                }
            } header: {
                HStack {
                    Text("Recurring")
                    Spacer()
                    Button {
                        showingAddRecurring = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.ledgerAccent)
                    }
                    .buttonStyle(.plain)
                }
            }

            // MARK: Transactions — empty / no-results states
            if account.transactionsArray.isEmpty {
                Section {
                    emptyTransactionsRow
                } header: {
                    transactionsSectionHeader
                }
            } else if filteredTransactions.isEmpty {
                Section {
                    if #available(iOS 17, *) {
                        ContentUnavailableView.search(text: transactionSearch)
                    }
                } header: {
                    transactionsSectionHeader
                }
            } else {
                // Date-grouped sections
                ForEach(groupedFilteredTransactions, id: \.group) { item in
                    Section(item.group.rawValue) {
                        ForEach(item.txs) { tx in
                            TransactionRow(transaction: tx)
                                .contentShape(Rectangle())
                                .onTapGesture { editingTransaction = tx }
                        }
                        .onDelete { offsets in deleteGrouped(offsets: offsets, in: item.txs) }
                    }
                }
            }
        }
        .searchable(text: $transactionSearch, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search transactions…")
        .navigationTitle(account.wrappedName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingAddTransaction = true
                    } label: {
                        Label("Add Transaction", systemImage: "plus")
                    }

                    Button {
                        showingCSVImport = true
                    } label: {
                        Label("Import CSV", systemImage: "arrow.down.doc")
                    }

                    Divider()

                    Button {
                        showingEditAccount = true
                    } label: {
                        Label("Edit Account", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete Account", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        // Add transaction sheet
        .sheet(isPresented: $showingAddTransaction) {
            AddEditTransactionView(account: account)
                .environment(\.managedObjectContext, ctx)
        }
        // Edit account sheet — onDelete propagates dismiss so this view doesn't
        // stay on the nav stack showing a deleted NSManagedObject.
        .sheet(isPresented: $showingEditAccount) {
            AddEditAccountView(account: account, onDelete: { dismiss() })
                .environment(\.managedObjectContext, ctx)
        }
        // Edit transaction sheet — driven by tapping a row
        .sheet(item: $editingTransaction) { tx in
            AddEditTransactionView(account: account, transaction: tx)
                .environment(\.managedObjectContext, ctx)
        }
        // Add asset sheet
        .sheet(isPresented: $showingAddAsset) {
            AddEditAssetView(account: account)
                .environment(\.managedObjectContext, ctx)
        }
        // Edit asset sheet — driven by tapping a row
        .sheet(item: $editingAsset) { a in
            AddEditAssetView(account: account, asset: a)
                .environment(\.managedObjectContext, ctx)
        }
        // Add recurring sheet
        .sheet(isPresented: $showingAddRecurring) {
            AddEditRecurringView(account: account)
                .environment(\.managedObjectContext, ctx)
        }
        // Edit recurring sheet — driven by tapping a row
        .sheet(item: $editingRecurring) { r in
            AddEditRecurringView(account: account, recurring: r)
                .environment(\.managedObjectContext, ctx)
        }
        // CSV import sheet
        .sheet(isPresented: $showingCSVImport) {
            CSVImportView(account: account)
                .environment(\.managedObjectContext, ctx)
        }
        // Debt payoff planner navigation
        .navigationDestination(isPresented: $showingDebtPayoff) {
            DebtPayoffView(account: account)
        }
        // Detect recurring patterns on first load
        .onAppear {
            let existing = account.recurringTransactionsArray
            detectedPatterns = RecurringDetectionService.detect(
                in: account.transactionsArray,
                excluding: existing
            )
        }
        // Confirm delete account
        .alert("Delete \(account.wrappedName)?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                ctx.delete(account)
                try? ctx.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All transactions in this account will also be deleted. This cannot be undone.")
        }
    }

    // MARK: - Sub-views

    private var transactionsSectionHeader: some View {
        HStack {
            Text("Transactions")
            Spacer()
            Button {
                showingAddTransaction = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.ledgerAccent)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyAssetsRow: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.pie")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No assets yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Add First Asset") {
                showingAddAsset = true
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var emptyRecurringRow: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No recurring transactions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Add Recurring") {
                showingAddRecurring = true
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var emptyTransactionsRow: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No transactions yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Add First Transaction") {
                showingAddTransaction = true
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.monoSubhead())
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func deleteRecurring(at offsets: IndexSet) {
        HapticService.impact(.rigid)
        let arr = account.recurringTransactionsArray
        offsets.map { arr[$0] }.forEach(ctx.delete)
        try? ctx.save()
    }

    private func deleteAssets(at offsets: IndexSet) {
        HapticService.impact(.rigid)
        let arr = account.assetsArray
        offsets.map { arr[$0] }.forEach(ctx.delete)
        try? ctx.save()
    }

    private func deleteGrouped(offsets: IndexSet, in txs: [CDTransaction]) {
        HapticService.impact(.rigid)
        offsets.map { txs[$0] }.forEach { tx in
            account.balance -= tx.amount
            ctx.delete(tx)
        }
        try? ctx.save()
    }

    private func createRecurringFromPattern(_ pattern: DetectedPattern) {
        HapticService.impact(.medium)
        let rule          = RecurringTransaction(context: ctx)
        rule.id           = UUID()
        rule.name         = pattern.name
        rule.amount       = pattern.amount
        rule.frequency    = pattern.frequency.rawValue
        rule.category     = pattern.sampleTransactions.first?.category ?? TransactionCategory.other.rawValue
        rule.isActive     = true
        rule.nextDueDate  = pattern.frequency.nextDate(after: Date())
        rule.account      = account
        try? ctx.save()
        // Remove from detected list so it doesn't re-appear immediately
        detectedPatterns.removeAll { $0.id == pattern.id }
        HapticService.success()
    }
}

// MARK: - Recurring Row
private struct RecurringRow: View {
    @ObservedObject var recurring: RecurringTransaction

    var body: some View {
        HStack(spacing: Theme.s12) {
            Image(systemName: recurring.transactionCategory.icon)
                .font(.body)
                .foregroundStyle(amountColor)
                .frame(width: 38, height: 38)
                .background(amountColor.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusS))

            VStack(alignment: .leading, spacing: 2) {
                Text(recurring.wrappedName)
                    .font(.body)
                Text(recurring.recurringFrequency.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(recurring.amount.asCurrency())
                    .font(Theme.monoBody())
                    .foregroundStyle(amountColor)
                if let next = recurring.nextDueDate {
                    Text(next, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, Theme.s4)
    }

    private var amountColor: Color {
        recurring.isExpense ? .ledgerNegative : .ledgerPositive
    }
}

// MARK: - Asset Row (account context — no live price yet)
private struct AssetDetailRow: View {
    @ObservedObject var asset: Asset

    var body: some View {
        HStack(spacing: Theme.s12) {
            Image(systemName: asset.assetKind.icon)
                .font(.body)
                .foregroundStyle(Color.ledgerAccent)
                .frame(width: 38, height: 38)
                .background(Color.ledgerAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusS))

            VStack(alignment: .leading, spacing: 2) {
                Text(asset.wrappedSymbol)
                    .font(.body.bold())
                Text(asset.assetKind.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(asset.costBasis.asCurrency())
                    .font(Theme.monoBody())
                    .fontWeight(.semibold)
                Text("qty \(asset.quantity, specifier: "%g")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Theme.s4)
    }
}

// MARK: - Transaction Row
private struct TransactionRow: View {
    @ObservedObject var transaction: CDTransaction

    var body: some View {
        HStack(spacing: Theme.s12) {
            Image(systemName: transaction.transactionCategory.icon)
                .font(.body)
                .foregroundStyle(amountColor)
                .frame(width: 38, height: 38)
                .background(amountColor.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusS))

            VStack(alignment: .leading, spacing: 2) {
                Text(rowTitle)
                    .font(.body)
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text(transaction.transactionCategory.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let date = transaction.date {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Text(transaction.amount.asCurrency())
                .font(Theme.monoBody())
                .foregroundStyle(amountColor)
        }
        .padding(.vertical, Theme.s4)
    }

    private var rowTitle: String {
        transaction.wrappedNotes.isEmpty
            ? transaction.transactionCategory.displayName
            : transaction.wrappedNotes
    }

    private var amountColor: Color {
        transaction.isExpense ? .ledgerNegative : .ledgerPositive
    }
}

#Preview {
    let ctx = PersistenceController.preview.container.viewContext
    let account = try! ctx.fetch(Account.fetchRequest()).first!
    return NavigationStack {
        AccountDetailView(account: account)
    }
    .environment(\.managedObjectContext, ctx)
}
