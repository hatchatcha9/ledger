import SwiftUI
import UserNotifications
import Charts

// MARK: - Local chart-data types

private enum TimeRange: String, CaseIterable {
    case sevenDays  = "7d"
    case thirtyDays = "30d"
    case allTime    = "All"
}

private struct BalancePoint: Identifiable {
    var id: Date { date }
    let date:  Date
    let value: Double
}

private struct CategorySlice: Identifiable {
    var id: String { category.rawValue }
    let category: TransactionCategory
    let amount:   Double
}

private struct MonthlyFlow: Identifiable {
    var id: String { "\(year)-\(month)-\(flowType)" }
    let year:       Int
    let month:      Int
    let monthLabel: String
    let flowType:   String   // "Income" or "Expenses"
    let amount:     Double
}

// MARK: - View

struct DashboardView: View {
    @Environment(\.managedObjectContext) private var ctx

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.createdAt)],
        animation: .default
    ) private var accounts: FetchedResults<Account>

    // Separate fetch so SwiftUI re-renders when any transaction changes —
    // not just when account.balance changes.
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.date)],
        animation: .default
    ) private var allTransactions: FetchedResults<CDTransaction>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.category)],
        animation: .default
    ) private var budgets: FetchedResults<Budget>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.nextDueDate)],
        predicate: NSPredicate(format: "isActive == YES"),
        animation: .default
    ) private var recurringRules: FetchedResults<RecurringTransaction>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.symbol)],
        animation: .default
    ) private var assets: FetchedResults<Asset>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.exitDate, order: .reverse)],
        animation: .default
    ) private var journalEntries: FetchedResults<JournalEntry>

    @EnvironmentObject private var prices: PriceService
    @EnvironmentObject private var quantStatus: QuantStatusService
    @EnvironmentObject private var signalService: QuantSignalService

    @State private var selectedRange: TimeRange = .thirtyDays
    @State private var showingChat = false
    @State private var showingAddAccount = false
    @AppStorage("currencyCode")         private var currencyCode  = "USD"
    @AppStorage("netWorthGoalEnabled")  private var goalEnabled   = false
    @AppStorage("netWorthGoalAmount")   private var goalAmount: Double = 0
    @AppStorage("fireMultiplier")       private var fireMultiplier: Double = 25

    @StateObject private var chatVM    = ChatViewModel()
    @State private var chatButtonPulse = false
    @State private var velocityAlerts: [VelocityAlert] = []
    @AppStorage("velocityDismissedDay") private var velocityDismissedDay = ""
    @State private var drillCategory: TransactionCategory? = nil
    @State private var drillMonth: DateComponents? = nil
    @State private var showAllTransactions    = false
    @State private var showingSettings        = false
    @State private var showingSubscriptions   = false
    @State private var showingForecast        = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.s16) {
                    if accounts.isEmpty {
                        emptyStateCard
                    }

                    HStack(spacing: Theme.s12) {
                        StatTile(
                            label: "Net Worth",
                            value: totalBalance.asCurrency(code: currencyCode),
                            change: netWorthChange30d.map { $0.asChangePercent() },
                            changePositive: netWorthChange30d.map { $0 >= 0 },
                            icon: "chart.line.uptrend.xyaxis"
                        )
                        StatTile(
                            label: "Saved This Month",
                            value: currentMonthSavings.asCurrency(code: currencyCode),
                            change: savingsRatePercent.map { "\(String(format: "%.0f", $0))% rate" },
                            changePositive: savingsRatePercent.map { $0 >= 0 },
                            icon: "arrow.down.circle"
                        )
                    }

                    monthOverMonthCard

                    if !velocityAlerts.isEmpty && !velocityBannerDismissedToday {
                        velocityBannerCard
                    }

                    botPulseCard

                    if goalEnabled && goalAmount > 0 {
                        goalCard
                    }
                    fireCard
                    tradeGoalCard
                    emergencyFundCard
                    subscriptionRadarCard
                    netWorthChartCard
                    cashFlowCard
                    forecastCard
                    if !budgets.isEmpty {
                        budgetCard
                    }
                    spendingChartCard
                    recentActivityCard
                }
                .padding(Theme.s16)
                .padding(.bottom, 80)   // room for the floating button
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack { SettingsView() }
            }
            .background(Color.ledgerGrouped)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    HapticService.impact(.medium)
                    chatVM.financialContext = buildFinancialContext()
                    showingChat = true
                } label: {
                    HStack(spacing: Theme.s8) {
                        Group {
                            if #available(iOS 17, *) {
                                Image(systemName: "sparkles")
                                    .symbolEffect(.pulse, options: .repeating)
                            } else {
                                Image(systemName: "sparkles")
                            }
                        }
                        Text("Ask Claude")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.s16)
                    .padding(.vertical, Theme.s12)
                    .background(Color.ledgerAccent, in: Capsule())
                    .shadow(color: Color.ledgerAccent.opacity(0.4), radius: 14, y: 6)
                    .scaleEffect(chatButtonPulse ? 1.025 : 1.0)
                    .animation(
                        .easeInOut(duration: 2.2).repeatForever(autoreverses: true),
                        value: chatButtonPulse
                    )
                }
                .buttonStyle(ScaleButtonStyle(pressedScale: 0.93))
                .padding(.trailing, Theme.s16)
                .padding(.bottom, Theme.s16)
                .onAppear {
                    chatButtonPulse = true
                    Task { await quantStatus.fetch() }
                }
            }
            // navigationDestination must be inside the NavigationStack context.
            .navigationDestination(isPresented: Binding(
                get: { drillCategory != nil },
                set: { if !$0 { drillCategory = nil } }
            )) {
                if let cat = drillCategory {
                    FilteredTransactionListView(
                        title: cat.displayName,
                        transactions: allTransactions.filter {
                            let cal = Calendar.current; let now = Date()
                            guard $0.transactionCategory == cat, let d = $0.date else { return false }
                            return cal.component(.year,  from: d) == cal.component(.year,  from: now)
                                && cal.component(.month, from: d) == cal.component(.month, from: now)
                        }
                    )
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { drillMonth != nil },
                set: { if !$0 { drillMonth = nil } }
            )) {
                if let dc = drillMonth {
                    FilteredTransactionListView(
                        title: monthLabel(dc),
                        transactions: allTransactions.filter {
                            guard let d = $0.date else { return false }
                            let cal = Calendar.current
                            return cal.component(.year,  from: d) == dc.year
                                && cal.component(.month, from: d) == dc.month
                        }
                    )
                }
            }
            .navigationDestination(isPresented: $showAllTransactions) {
                FilteredTransactionListView(
                    title: "All Transactions",
                    transactions: Array(allTransactions)
                )
            }
            .navigationDestination(isPresented: $showingForecast) {
                CashFlowForecastView(
                    recurringRules: Array(recurringRules),
                    currentBalance: totalBalance,
                    currencyCode:   currencyCode
                )
            }
        }
        .sheet(isPresented: $showingChat) {
            ChatView(viewModel: chatVM)
        }
        .sheet(isPresented: $showingAddAccount) {
            AddEditAccountView()
                .environment(\.managedObjectContext, ctx)
        }
        .sheet(isPresented: $showingSubscriptions) {
            SubscriptionRadarView(subscriptions: SubscriptionRadarService.detect(from: Array(allTransactions)))
        }
        .onAppear {
            velocityAlerts = SpendingVelocityService.anomalies(from: Array(allTransactions))
            SpendingVelocityService.fireNotifications(for: velocityAlerts)
            BudgetAlertService.checkAndNotify(budgets: Array(budgets),
                                              transactions: Array(allTransactions))
            // Feature 4 — Thesis change alerts: notify when price drops 20%+ below entry
            let openTrades = journalEntries.filter { $0.isOpen }
            let code = currencyCode  // capture on main thread before background callback
            for trade in openTrades {
                let sym   = trade.wrappedSymbol
                let entry = trade.entryPrice
                guard entry > 0,
                      let current = prices.prices[sym],
                      current < entry * 0.80
                else { continue }
                let notifID = "thesis-alert-\(sym)-\(Calendar.current.component(.weekOfYear, from: .now))"
                let pct     = Int(((entry - current) / entry) * 100)
                let body    = "\(sym) is down \(pct)% from your entry (\(current.asCurrency(code: code)) vs \(entry.asCurrency(code: code))). Still conviction?"
                UNUserNotificationCenter.current().getPendingNotificationRequests { pending in
                    guard !pending.contains(where: { $0.identifier == notifID }) else { return }
                    let content       = UNMutableNotificationContent()
                    content.title     = "Review your thesis: \(sym)"
                    content.body      = body
                    content.sound     = .default
                    let req = UNNotificationRequest(identifier: notifID, content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
                }
            }
        }
        .task {
            await signalService.fetch(symbols: ["BTC", "ETH", "SOL"])
        }
        // Fetch FX rates as soon as the dashboard appears so net worth and
        // cash-flow figures are correct before the user visits Portfolio.
        .task(id: accounts.map(\.wrappedCurrency).sorted().joined()) {
            let currencies = Array(Set(accounts.map(\.wrappedCurrency)))
            guard currencies.contains(where: { $0 != "USD" }) else { return }
            await prices.refresh(assets: [], watchlist: [], currencies: currencies)
        }
    }

    // MARK: - Claude context builder

    private func buildFinancialContext() -> String {
        let cal = Calendar.current
        let now = Date()
        var lines = [String]()

        // Accounts
        lines.append("ACCOUNTS (\(accounts.count)):")
        for acc in accounts {
            lines.append("  \(acc.wrappedName) [\(acc.accountType.displayName)]: \(acc.balance.asCurrency(code: currencyCode))")
        }
        lines.append("  Total Balance: \(totalBalance.asCurrency(code: currencyCode))")

        // Portfolio assets
        if !assets.isEmpty {
            lines.append("\nPORTFOLIO ASSETS:")
            for asset in assets {
                let line = "  \(asset.wrappedSymbol) – qty \(String(format: "%g", asset.quantity)), avg cost \(asset.avgCost.asCurrency(code: currencyCode)), cost basis \(asset.costBasis.asCurrency(code: currencyCode))"
                lines.append(line)
            }
        }

        // Monthly cash flow
        let year  = cal.component(.year,  from: now)
        let month = cal.component(.month, from: now)
        let totals = monthlyTotals(year: year, month: month)
        let savings = totals.income - totals.expenses
        let rate    = totals.income > 0 ? (savings / totals.income * 100) : 0
        lines.append("\nTHIS MONTH:")
        lines.append("  Income:   \(totals.income.asCurrency(code: currencyCode))")
        lines.append("  Expenses: \(totals.expenses.asCurrency(code: currencyCode))")
        lines.append("  Saved:    \(savings.asCurrency(code: currencyCode)) (\(String(format: "%.1f", rate))% rate)")

        // Journal
        let closed   = journalEntries.filter { !$0.isOpen }
        let wins     = closed.filter { ($0.realisedPnL ?? 0) > 0 }.count
        let totalPnL = closed.reduce(0) { $0 + ($1.realisedPnL ?? 0) }
        if !closed.isEmpty {
            lines.append("\nTRADING JOURNAL:")
            lines.append("  Closed trades: \(closed.count), Win rate: \(Int((Double(wins) / Double(closed.count)) * 100))%")
            lines.append("  Total P&L: \(totalPnL.asCurrency(code: currencyCode))")
            lines.append("  Open positions: \(journalEntries.filter { $0.isOpen }.count)")
        }

        // Goal
        if goalEnabled && goalAmount > 0 {
            let progress = goalAmount > 0 ? min(totalBalance / goalAmount * 100, 100) : 0
            lines.append("\nNET WORTH GOAL: \(goalAmount.asCurrency(code: currencyCode)) (\(String(format: "%.1f", progress))% reached)")
        }

        if let qs = quantStatus.status {
            lines.append("\nQUANT SYSTEM (LIVE):")
            lines.append(qs.contextString)
        }

        // Feature 5 — Emergency fund
        if avgMonthlyExpenses > 0 {
            lines.append("\nEMERGENCY FUND:")
            lines.append("  Liquid assets: \(liquidBalance.asCurrency(code: currencyCode))")
            lines.append("  Avg monthly expenses (6mo): \(avgMonthlyExpenses.asCurrency(code: currencyCode))")
            lines.append("  Months covered: \(String(format: "%.1f", monthsCovered)) (goal: 6.0)")
        }

        // Feature 6 — Spending anomaly context (current vs prior 3 full months by category)
        let cal6 = Calendar.current
        let startOfCurrentMonth: Date = {
            var comps = cal6.dateComponents([.year, .month], from: now)
            comps.day = 1
            return cal6.date(from: comps) ?? now
        }()
        if let threeMonthsAgo = cal6.date(byAdding: .month, value: -3, to: startOfCurrentMonth) {
            // Exclude current (partial) month so the baseline is 3 complete months
            let prior3 = allTransactions.filter {
                guard let d = $0.date else { return false }
                return $0.amount < 0 && d >= threeMonthsAgo && d < startOfCurrentMonth
            }
            var catTotals: [String: Double] = [:]
            for tx in prior3 {
                catTotals[tx.transactionCategory.displayName, default: 0] += abs(tx.amount)
            }
            if !catTotals.isEmpty {
                lines.append("\nSPENDING BY CATEGORY (prior 3 months):")
                for (cat, total) in catTotals.sorted(by: { $0.value > $1.value }).prefix(8) {
                    lines.append("  \(cat): \(total.asCurrency(code: currencyCode))")
                }
                // Current month vs prior-month average
                let currentCatTotals = allTransactions.filter {
                    guard let d = $0.date else { return false }
                    return $0.amount < 0 && d >= startOfCurrentMonth
                }.reduce(into: [String: Double]()) { $0[$1.transactionCategory.displayName, default: 0] += abs($1.amount) }
                let anomalies = currentCatTotals.filter { cat, amt in
                    let avg3 = (catTotals[cat] ?? 0) / 3
                    return avg3 > 0 && amt > avg3 * 1.5
                }
                if !anomalies.isEmpty {
                    lines.append("  ANOMALIES this month (>1.5x prior avg):")
                    for (cat, amt) in anomalies {
                        let avg3 = (catTotals[cat] ?? 0) / 3
                        lines.append("    \(cat): \(amt.asCurrency(code: currencyCode)) vs avg \(avg3.asCurrency(code: currencyCode))/mo")
                    }
                }
            }
        }

        // Feature 7 — Goal conflict context
        let openDebts = accounts.filter { $0.accountType == .creditCard || $0.accountType == .loan }
        let totalDebt = openDebts.reduce(0) { $0 + abs($1.balance) }
        if totalDebt > 0 {
            lines.append("\nDEBT vs FI/RE CONFLICT:")
            lines.append("  Total debt: \(totalDebt.asCurrency(code: currencyCode))")
            lines.append("  FI/RE target: \(fireNumber.asCurrency(code: currencyCode))")
            lines.append("  Net investable assets: \((totalBalance - totalDebt).asCurrency(code: currencyCode))")
            lines.append("  FI/RE gap: \(max(0, fireNumber - totalBalance + totalDebt).asCurrency(code: currencyCode))")
        }

        // Feature 8 — Trade-to-goal attribution
        if let qs = quantStatus.status, qs.dailyPnlMain != 0 {
            let monthlyPaper = qs.dailyPnlMain * 21
            lines.append("\nTRADE→GOAL ATTRIBUTION (paper):")
            lines.append("  Bot daily P&L: \(qs.dailyPnlMain.asCurrency(code: currencyCode))")
            lines.append("  Est. monthly paper: \(monthlyPaper.asCurrency(code: currencyCode))")
            if currentMonthSavings > 0 {
                let pct = (monthlyPaper / currentMonthSavings) * 100
                lines.append("  As % of monthly savings: \(String(format: "%.1f", pct))%")
            }
        }

        // Subscription radar
        let subs = SubscriptionRadarService.detect(from: Array(allTransactions))
        if !subs.isEmpty {
            let annual = subs.reduce(0) { $0 + $1.annualCost }
            lines.append("\nSUBSCRIPTIONS: \(subs.count) detected, \(annual.asCurrency(code: currencyCode))/year")
            for s in subs.prefix(5) {
                lines.append("  \(s.name): \(s.avgAmount.asCurrency(code: currencyCode))/\(s.frequency.lowercased())")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Computed scalars

    private var velocityBannerDismissedToday: Bool {
        velocityDismissedDay == todayString()
    }

    private func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: .now)
    }

    private var totalBalance: Double {
        accounts.reduce(0) { $0 + prices.usdValue(of: $1.balance, currency: $1.wrappedCurrency) }
    }

    // 30-day change for the net worth tile.
    private var netWorthChange30d: Double? {
        let history = netWorthHistory(range: .thirtyDays)
        guard let first = history.first, abs(first.value) > 0,
              let last = history.last else { return nil }
        return ((last.value - first.value) / abs(first.value)) * 100
    }

    // MARK: - Monthly cash flow helpers

    private func monthlyTotals(year: Int, month: Int) -> (income: Double, expenses: Double) {
        let cal = Calendar.current
        var income = 0.0, expenses = 0.0
        for tx in allTransactions {
            guard let d = tx.date,
                  cal.component(.year,  from: d) == year,
                  cal.component(.month, from: d) == month else { continue }
            let currency = tx.account?.wrappedCurrency ?? "USD"
            let converted = prices.usdValue(of: tx.amount, currency: currency)
            if converted > 0 { income   += converted }
            else             { expenses += abs(converted) }
        }
        return (income, expenses)
    }

    // MARK: - Month-over-month

    private var lastMonthTotals: (income: Double, expenses: Double) {
        guard let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: .now) else {
            return (0, 0)
        }
        let cal = Calendar.current
        return monthlyTotals(year: cal.component(.year,  from: lastMonth),
                             month: cal.component(.month, from: lastMonth))
    }

    private var currentMonthIncome: Double {
        let cal   = Calendar.current
        let now   = Date()
        return monthlyTotals(year: cal.component(.year, from: now),
                             month: cal.component(.month, from: now)).income
    }

    private var currentMonthExpenses: Double {
        let cal   = Calendar.current
        let now   = Date()
        return monthlyTotals(year: cal.component(.year, from: now),
                             month: cal.component(.month, from: now)).expenses
    }

    private var currentMonthSavings: Double { currentMonthIncome - currentMonthExpenses }

    private var savingsRatePercent: Double? {
        guard currentMonthIncome > 0 else { return nil }
        return (currentMonthSavings / currentMonthIncome) * 100
    }

    private var monthlyFlowData: [MonthlyFlow] {
        let cal = Calendar.current
        let now = Date()
        return (0..<6).reversed().flatMap { offset -> [MonthlyFlow] in
            guard let d = cal.date(byAdding: .month, value: -offset, to: now) else { return [] }
            let y = cal.component(.year,  from: d)
            let m = cal.component(.month, from: d)
            let label = d.formatted(.dateTime.month(.abbreviated))
            let (income, expenses) = monthlyTotals(year: y, month: m)
            return [
                MonthlyFlow(year: y, month: m, monthLabel: label, flowType: "Income",   amount: income),
                MonthlyFlow(year: y, month: m, monthLabel: label, flowType: "Expenses", amount: expenses)
            ]
        }
    }

    // MARK: - Recent activity

    private var recentTransactions: [CDTransaction] {
        allTransactions
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .prefix(6)
            .map { $0 }
    }

    // MARK: - Net Worth History

    private func netWorthHistory(range: TimeRange) -> [BalancePoint] {
        let calendar = Calendar.current
        let today    = calendar.startOfDay(for: .now)

        // Determine window start.
        let startDate: Date = {
            switch range {
            case .sevenDays:
                return calendar.date(byAdding: .day, value: -6, to: today) ?? today
            case .thirtyDays:
                return calendar.date(byAdding: .day, value: -29, to: today) ?? today
            case .allTime:
                let earliest = allTransactions.compactMap(\.date).min()
                return earliest.map { calendar.startOfDay(for: $0) } ?? today
            }
        }()

        // Sort ascending so we can walk forward in time.
        let sorted = allTransactions.sorted {
            ($0.date ?? .distantPast) < ($1.date ?? .distantPast)
        }

        // Starting point: current NW minus every transaction that has ever occurred.
        let currentNW  = totalBalance
        let sumAllTx   = sorted.reduce(0) { $0 + $1.amount }
        let initialNW  = currentNW - sumAllTx

        // Add every transaction before our window to reach the balance at startDate.
        let preWindowSum = sorted
            .filter { ($0.date.map { calendar.startOfDay(for: $0) } ?? .distantPast) < startDate }
            .reduce(0) { $0 + $1.amount }

        var running = initialNW + preWindowSum

        // Transactions that fall within [startDate, today], sorted ascending.
        let windowTx = sorted.filter {
            guard let d = $0.date else { return false }
            let day = calendar.startOfDay(for: d)
            return day >= startDate && day <= today
        }

        var txIdx  = 0
        var points = [BalancePoint]()
        var day    = startDate

        while day <= today {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            // Consume all transactions whose day is before nextDay.
            while txIdx < windowTx.count {
                guard let txDate = windowTx[txIdx].date else { txIdx += 1; continue }
                guard calendar.startOfDay(for: txDate) < nextDay else { break }
                running += windowTx[txIdx].amount
                txIdx   += 1
            }
            points.append(BalancePoint(date: day, value: running))
            day = nextDay
        }

        return points
    }

    // MARK: - Spending by Category

    private var currentMonthSpending: [CategorySlice] {
        let calendar = Calendar.current
        let now      = Date()
        let year     = calendar.component(.year,  from: now)
        let month    = calendar.component(.month, from: now)

        var totals = [TransactionCategory: Double]()
        for tx in allTransactions {
            guard tx.amount < 0, let d = tx.date else { continue }
            guard calendar.component(.year,  from: d) == year,
                  calendar.component(.month, from: d) == month else { continue }
            totals[tx.transactionCategory, default: 0] += abs(tx.amount)
        }

        return totals
            .map { CategorySlice(category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    // MARK: - Chart cards

    // MARK: - Month-over-month card

    @ViewBuilder
    private var monthOverMonthCard: some View {
        let last = lastMonthTotals
        if last.income > 0 || last.expenses > 0 {
            let incomeChg  = last.income   > 0 ? ((currentMonthIncome   - last.income)   / last.income)   * 100 : 0.0
            let expenseChg = last.expenses > 0 ? ((currentMonthExpenses - last.expenses) / last.expenses) * 100 : 0.0
            let lastSaved  = last.income - last.expenses
            let thisSaved  = currentMonthSavings

            VStack(alignment: .leading, spacing: Theme.s12) {
                Label("vs Last Month", systemImage: "arrow.left.arrow.right.circle")
                    .font(.subheadline.bold())

                HStack(spacing: 0) {
                    momCell(label: "Income",
                            current: currentMonthIncome,
                            change: incomeChg,
                            positive: incomeChg >= 0)
                    Divider().frame(height: 44)
                    momCell(label: "Expenses",
                            current: currentMonthExpenses,
                            change: expenseChg,
                            positive: expenseChg <= 0)
                    Divider().frame(height: 44)
                    momCell(label: "Saved",
                            current: thisSaved,
                            change: lastSaved != 0 ? ((thisSaved - lastSaved) / abs(lastSaved)) * 100 : 0,
                            positive: thisSaved >= lastSaved)
                }
            }
            .padding(Theme.s16)
            .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
        }
    }

    private func momCell(label: String, current: Double, change: Double, positive: Bool) -> some View {
        let sign = change >= 0 ? "+" : ""
        return VStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(current.asCurrency(code: currencyCode))
                .font(Theme.monoCaption().bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 2) {
                Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 8, weight: .bold))
                Text("\(sign)\(String(format: "%.0f", change))%")
                    .font(.system(size: 10))
            }
            .foregroundStyle(positive ? Color.ledgerPositive : Color.ledgerNegative)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.s4)
    }

    @ViewBuilder
    private var netWorthChartCard: some View {
        VStack(alignment: .leading, spacing: Theme.s12) {
            HStack {
                Label("Net Worth", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline.bold())
                Spacer()
                Picker("Range", selection: $selectedRange) {
                    ForEach(TimeRange.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .labelsHidden()
            }

            let points = netWorthHistory(range: selectedRange)
            let isFlat = points.allSatisfy { $0.value == points.first?.value }

            if points.isEmpty {
                emptyChartPlaceholder(icon: "chart.line.uptrend.xyaxis",
                                      message: "Add transactions to see history")
            } else {
                let minVal       = points.map(\.value).min() ?? 0
                let maxVal       = points.map(\.value).max() ?? 0
                let range        = maxVal - minVal
                let padding      = max(range * 0.12, 50)
                let trendColor   = isFlat
                    ? Color.ledgerAccent
                    : ((points.last?.value ?? 0) >= (points.first?.value ?? 0)
                        ? Color.ledgerPositive : Color.ledgerNegative)

                Chart(points) { point in
                    LineMark(
                        x: .value("Date",  point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(trendColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    AreaMark(
                        x: .value("Date",  point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [trendColor.opacity(0.15), trendColor.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
                .frame(height: 150)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                            .foregroundStyle(Color(.separator).opacity(0.5))
                        AxisValueLabel(
                            format: selectedRange == .allTime
                                ? .dateTime.month(.abbreviated).year(.twoDigits)
                                : .dateTime.month(.abbreviated).day()
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                            .foregroundStyle(Color(.separator).opacity(0.5))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(compactCurrency(v))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartYScale(domain: (minVal - padding)...(maxVal + padding))
            }
        }
        .padding(Theme.s16)
        .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
    }

    // Each spending category gets a stable distinct color so the bar chart
    // is immediately readable — not just a wall of the same accent shade.
    private func categoryColor(_ category: TransactionCategory) -> Color {
        let palette: [Color] = [
            .ledgerAccent, .ledgerPositive, .orange, .purple, .pink,
            .cyan, .yellow, .indigo, .teal, .red
        ]
        let index = abs(category.rawValue.hashValue) % palette.count
        return palette[index]
    }

    @ViewBuilder
    private var spendingChartCard: some View {
        let slices = currentMonthSpending
        let maxAmt = slices.first?.amount ?? 1

        VStack(alignment: .leading, spacing: Theme.s12) {
            HStack {
                Label("Spending", systemImage: "chart.bar.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text("Tap to drill in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if slices.isEmpty {
                emptyChartPlaceholder(icon: "chart.pie.fill",
                                      message: "No expenses recorded this month")
            } else {
                VStack(spacing: Theme.s8) {
                    ForEach(slices) { slice in
                        Button {
                            HapticService.impact(.light)
                            drillCategory = slice.category
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: slice.category.icon)
                                        .font(.caption)
                                        .foregroundStyle(categoryColor(slice.category))
                                        .frame(width: 14)
                                    Text(slice.category.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(slice.amount.asCurrency(code: currencyCode))
                                        .font(Theme.monoCaption())
                                        .foregroundStyle(.primary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(categoryColor(slice.category).opacity(0.18))
                                            .frame(height: 6)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(categoryColor(slice.category))
                                            .frame(width: geo.size.width * min(slice.amount / maxAmt, 1.0), height: 6)
                                    }
                                }
                                .frame(height: 6)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(Theme.s16)
        .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
    }

    // MARK: - Cash flow card

    @ViewBuilder
    private var cashFlowCard: some View {
        let data = monthlyFlowData
        let hasData = data.contains { $0.amount > 0 }

        VStack(alignment: .leading, spacing: Theme.s12) {
            HStack {
                Label("Cash Flow", systemImage: "arrow.left.arrow.right")
                    .font(.subheadline.bold())
                Spacer()
                Text("Last 6 months")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !hasData {
                emptyChartPlaceholder(icon: "arrow.left.arrow.right",
                                      message: "No transactions yet")
            } else {
                // Legend
                HStack(spacing: Theme.s12) {
                    Spacer()
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.ledgerPositive).frame(width: 12, height: 8)
                        Text("Income").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.ledgerNegative).frame(width: 12, height: 8)
                        Text("Expenses").font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Chart(data) { item in
                    BarMark(
                        x: .value("Month",  item.monthLabel),
                        y: .value("Amount", item.amount),
                        width: .ratio(0.4)
                    )
                    .foregroundStyle(item.flowType == "Income" ? Color.ledgerPositive : Color.ledgerNegative)
                    .position(by: .value("Type", item.flowType))
                    .cornerRadius(3)
                }
                .chartLegend(.hidden)
                .frame(height: 150)
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel().font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(Color(.separator).opacity(0.5))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(compactCurrency(v)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Summary row
                let saved = currentMonthSavings
                HStack {
                    Label(saved >= 0 ? "Saved this month" : "Overspent this month",
                          systemImage: saved >= 0 ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(saved >= 0 ? .ledgerPositive : .ledgerNegative)
                    Spacer()
                    Text((saved >= 0 ? "+" : "") + saved.asCurrency(code: currencyCode))
                        .font(Theme.monoCaption().bold())
                        .foregroundStyle(saved >= 0 ? .ledgerPositive : .ledgerNegative)
                }

                // Tappable month drill-through buttons
                let cal = Calendar.current
                let distinctMonths: [DateComponents] = {
                    var seen = Set<String>()
                    return data.compactMap { item -> DateComponents? in
                        let key = "\(item.year)-\(item.month)"
                        guard seen.insert(key).inserted else { return nil }
                        return DateComponents(year: item.year, month: item.month)
                    }
                }()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.s8) {
                        ForEach(distinctMonths, id: \.self) { dc in
                            Button {
                                HapticService.impact(.light)
                                drillMonth = dc
                            } label: {
                                let label: String = {
                                    guard let y = dc.year, let m = dc.month,
                                          let d = cal.date(from: DateComponents(year: y, month: m)) else {
                                        return "?"
                                    }
                                    return d.formatted(.dateTime.month(.abbreviated))
                                }()
                                Text(label)
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.ledgerAccent)
                                    .padding(.horizontal, Theme.s8)
                                    .padding(.vertical, 4)
                                    .background(Color.ledgerAccent.opacity(0.1), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(Theme.s16)
        .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
    }

    // MARK: - Recent activity card

    @ViewBuilder
    private var recentActivityCard: some View {
        let recent = recentTransactions
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: Theme.s12) {
                HStack {
                    Label("Recent Activity", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.bold())
                    Spacer()
                    Button("See All") {
                        HapticService.impact(.light)
                        showAllTransactions = true
                    }
                    .font(.caption)
                    .foregroundStyle(Color.ledgerAccent)
                }

                ForEach(Array(recent.enumerated()), id: \.offset) { idx, tx in
                    HStack(spacing: Theme.s12) {
                        Image(systemName: tx.transactionCategory.icon)
                            .font(.footnote)
                            .foregroundStyle(tx.isExpense ? Color.ledgerNegative : Color.ledgerPositive)
                            .frame(width: 32, height: 32)
                            .background(
                                (tx.isExpense ? Color.ledgerNegative : Color.ledgerPositive).opacity(0.1),
                                in: RoundedRectangle(cornerRadius: Theme.radiusS)
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(tx.wrappedNotes.isEmpty ? tx.transactionCategory.displayName : tx.wrappedNotes)
                                .font(.subheadline)
                                .lineLimit(1)
                            if let accountName = tx.account?.wrappedName {
                                Text(accountName)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 1) {
                            Text(tx.amount.asCurrency(code: currencyCode))
                                .font(Theme.monoCaption())
                                .foregroundStyle(tx.isExpense ? .ledgerNegative : .ledgerPositive)
                            if let date = tx.date {
                                Text(date, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    if idx < recent.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(Theme.s16)
            .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
        }
    }

    // MARK: - Cash flow forecast card

    private func projectedBalance(daysFromNow days: Int) -> Double {
        let cal    = Calendar.current
        let target = cal.date(byAdding: .day, value: days, to: .now) ?? .now
        var proj   = totalBalance
        for rule in recurringRules {
            var next = rule.nextDueDate ?? .distantFuture
            while next <= target {
                proj += rule.amount
                let advanced = rule.recurringFrequency.nextDate(after: next)
                guard advanced > next else { break }
                next = advanced
            }
        }
        return proj
    }

    @ViewBuilder
    private var forecastCard: some View {
        if recurringRules.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: Theme.s12) {
                Label("Balance Forecast", systemImage: "calendar.badge.clock")
                    .font(.subheadline.bold())

                Text("Based on your recurring transactions")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    forecastPill(label: "30 days",  amount: projectedBalance(daysFromNow: 30))
                    Divider().frame(height: 40)
                    forecastPill(label: "60 days",  amount: projectedBalance(daysFromNow: 60))
                    Divider().frame(height: 40)
                    forecastPill(label: "90 days",  amount: projectedBalance(daysFromNow: 90))
                }
                .padding(.top, Theme.s4)

                Button {
                    HapticService.impact(.light)
                    showingForecast = true
                } label: {
                    HStack {
                        Text("View Full Forecast")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.ledgerAccent)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(Color.ledgerAccent.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.s16)
            .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
        }
    }

    private func forecastPill(label: String, amount: Double) -> some View {
        let delta = amount - totalBalance
        return VStack(spacing: 3) {
            Text(amount.asCurrency(code: currencyCode))
                .font(Theme.monoCaption().bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(delta >= 0 ? "+\(delta.asCurrency(code: currencyCode))" : delta.asCurrency(code: currencyCode))
                .font(.system(size: 10))
                .foregroundStyle(Color.changeColor(for: delta))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Emergency Fund Meter

    private var liquidBalance: Double {
        accounts
            .filter { [.checking, .savings, .cash].contains($0.accountType) }
            .reduce(0) { $0 + prices.usdValue(of: $1.balance, currency: $1.wrappedCurrency) }
    }

    private var avgMonthlyExpenses: Double {
        let cal = Calendar.current
        guard let sixMonthsAgo = cal.date(byAdding: .month, value: -6, to: .now) else { return 0 }
        let recent = allTransactions.filter { ($0.date ?? .distantPast) >= sixMonthsAgo && $0.amount < 0 }
        guard !recent.isEmpty else { return 0 }
        let total  = recent.reduce(0) { $0 + abs($1.amount) }
        // Divide by actual months with data, capped at 6
        let uniqueMonths = Set(recent.compactMap { tx -> String? in
            guard let d = tx.date else { return nil }
            let c = cal.dateComponents([.year, .month], from: d)
            return "\(c.year ?? 0)-\(c.month ?? 0)"
        }).count
        return total / Double(max(1, uniqueMonths))
    }

    private var monthsCovered: Double {
        guard avgMonthlyExpenses > 0 else { return 0 }
        return liquidBalance / avgMonthlyExpenses
    }

    @ViewBuilder
    private var emergencyFundCard: some View {
        if avgMonthlyExpenses > 0 {
            let covered  = monthsCovered
            let ratio    = min(covered / 6.0, 1.0)
            let color: Color = covered >= 6 ? .ledgerPositive : covered >= 3 ? .orange : .ledgerNegative
            let label:  String = covered >= 6 ? "Fully funded" : covered >= 3 ? "Getting there" : "Build this up"

            VStack(alignment: .leading, spacing: Theme.s12) {
                Label("Emergency Fund", systemImage: "umbrella.fill")
                    .font(.subheadline.bold())

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", covered))
                        .font(Theme.monoTitle2())
                        .foregroundStyle(color)
                    Text("months covered")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(label)
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(color.opacity(0.12), in: Capsule())
                        .foregroundStyle(color)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color(.systemFill)).frame(height: 8)
                        RoundedRectangle(cornerRadius: 4).fill(color)
                            .frame(width: geo.size.width * ratio, height: 8)
                            .animation(.spring(response: 0.8, dampingFraction: 0.8), value: ratio)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text(liquidBalance.asCurrency(code: currencyCode) + " liquid")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("of " + (avgMonthlyExpenses * 6).asCurrency(code: currencyCode) + " goal (6 mo.)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(Theme.s16)
            .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
        }
    }

    // MARK: - Trade-to-Goal Attribution

    @ViewBuilder
    private var tradeGoalCard: some View {
        let monthlyGap: Double = {
            guard fireNumber > totalBalance, currentMonthSavings > 0 else { return 0 }
            return (fireNumber - totalBalance) / max(1, Double(Int((fireNumber - totalBalance) / currentMonthSavings)))
        }()
        let dailyPnL = quantStatus.status?.dailyPnlMain ?? 0
        let monthlyPaper = dailyPnL * 21  // ~21 trading days
        let monthsAttributed = monthlyGap > 0 ? monthlyPaper / monthlyGap : 0

        if fireNumber > 0, dailyPnL != 0 {
            VStack(alignment: .leading, spacing: Theme.s12) {
                HStack(spacing: Theme.s8) {
                    Label("Bot → FI/RE", systemImage: "bolt.heart.fill")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("PAPER")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange, in: Capsule())
                }

                HStack(spacing: 0) {
                    VStack(spacing: 2) {
                        Text("Daily P&L")
                            .font(.caption2).foregroundStyle(.tertiary)
                        let sign = dailyPnL >= 0 ? "+" : ""
                        Text("\(sign)\(dailyPnL.asCurrency(code: currencyCode))")
                            .font(Theme.monoCaption().bold())
                            .foregroundStyle(Color.changeColor(for: dailyPnL))
                    }
                    .frame(maxWidth: .infinity)

                    Divider().frame(height: 32)

                    VStack(spacing: 2) {
                        Text("Est. Monthly")
                            .font(.caption2).foregroundStyle(.tertiary)
                        let sign = monthlyPaper >= 0 ? "+" : ""
                        Text("\(sign)\(monthlyPaper.asCurrency(code: currencyCode))")
                            .font(Theme.monoCaption().bold())
                            .foregroundStyle(Color.changeColor(for: monthlyPaper))
                    }
                    .frame(maxWidth: .infinity)

                    if monthsAttributed > 0 {
                        Divider().frame(height: 32)
                        VStack(spacing: 2) {
                            Text("FI/RE Boost")
                                .font(.caption2).foregroundStyle(.tertiary)
                            Text(String(format: "+%.1f mo.", monthsAttributed))
                                .font(Theme.monoCaption().bold())
                                .foregroundStyle(.ledgerPositive)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, Theme.s4)
                .background(Color(.secondarySystemFill).opacity(0.5),
                            in: RoundedRectangle(cornerRadius: Theme.radiusS))

                Text("If paper results transferred to savings")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(Theme.s16)
            .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusM)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1))
        }
    }

    // MARK: - Subscription Radar Summary Card

    @ViewBuilder
    private var subscriptionRadarCard: some View {
        let subs = SubscriptionRadarService.detect(from: Array(allTransactions))
        if !subs.isEmpty {
            let annual    = subs.reduce(0) { $0 + $1.annualCost }
            let increases = subs.filter { $0.priceChange ?? 0 > 0 }.count

            Button {
                HapticService.impact(.light)
                showingSubscriptions = true
            } label: {
                VStack(alignment: .leading, spacing: Theme.s12) {
                    HStack {
                        Label("Subscription Radar", systemImage: "repeat.circle.fill")
                            .font(.subheadline.bold())
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold()).foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 0) {
                        VStack(spacing: 2) {
                            Text("Detected")
                                .font(.caption2).foregroundStyle(.tertiary)
                            Text("\(subs.count)")
                                .font(.title3.bold()).foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        Divider().frame(height: 32)
                        VStack(spacing: 2) {
                            Text("Annual Cost")
                                .font(.caption2).foregroundStyle(.tertiary)
                            Text(annual.asCurrency(code: currencyCode))
                                .font(Theme.monoBody().bold()).foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        if increases > 0 {
                            Divider().frame(height: 32)
                            VStack(spacing: 2) {
                                Text("Price ↑")
                                    .font(.caption2).foregroundStyle(.tertiary)
                                Text("\(increases)")
                                    .font(.title3.bold()).foregroundStyle(.ledgerNegative)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, Theme.s4)
                    .background(Color(.secondarySystemFill).opacity(0.5),
                                in: RoundedRectangle(cornerRadius: Theme.radiusS))
                }
                .padding(Theme.s16)
                .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func emptyChartPlaceholder(icon: String, message: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: Theme.s4) {
                Image(systemName: icon)
                    .font(.largeTitle)
                    .foregroundStyle(.quaternary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.quaternary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(height: 120)
    }

    // MARK: - Goal card

    private var goalProgress: Double {
        guard goalAmount > 0 else { return 0 }
        return min(totalBalance / goalAmount, 1.0)
    }

    private var projectedGoalDate: Date? {
        let remaining = goalAmount - totalBalance
        guard remaining > 0 else { return nil }
        let history = netWorthHistory(range: .thirtyDays)
        guard history.count >= 2,
              let first = history.first,
              let last  = history.last,
              last.value > first.value else { return nil }
        let dailyGrowth = (last.value - first.value) / Double(history.count - 1)
        guard dailyGrowth > 0 else { return nil }
        let days = Int(remaining / dailyGrowth)
        return Calendar.current.date(byAdding: .day, value: days, to: .now)
    }

    @ViewBuilder
    private var goalCard: some View {
        VStack(alignment: .leading, spacing: Theme.s12) {
            Label("Net Worth Goal", systemImage: "target")
                .font(.subheadline.bold())

            HStack {
                Text(totalBalance.asCurrency(code: currencyCode))
                    .font(Theme.monoSubhead())
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: totalBalance)
                Text("of")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(goalAmount.asCurrency(code: currencyCode))
                    .font(Theme.monoSubhead())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(goalProgress * 100))%")
                    .font(Theme.monoSubhead().bold())
                    .foregroundStyle(goalProgress >= 1 ? .ledgerPositive : .ledgerAccent)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: goalProgress)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(goalProgress >= 1 ? Color.ledgerPositive : Color.ledgerAccent)
                        .frame(width: geo.size.width * goalProgress, height: 8)
                        .animation(.spring(response: 0.8, dampingFraction: 0.8), value: goalProgress)
                }
            }
            .frame(height: 8)

            if goalProgress >= 1 {
                Text("Goal reached!")
                    .font(.caption)
                    .foregroundStyle(.ledgerPositive)
            } else if let projected = projectedGoalDate {
                Text("On track · est. \(projected.formatted(.dateTime.month(.abbreviated).day().year()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\((goalAmount - totalBalance).asCurrency(code: currencyCode)) remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.s16)
        .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
    }

    // MARK: - Budget card

    @ViewBuilder
    private var budgetCard: some View {
        let calendar = Calendar.current
        let now = Date()
        let year  = calendar.component(.year,  from: now)
        let month = calendar.component(.month, from: now)

        VStack(alignment: .leading, spacing: Theme.s12) {
            Label("Budgets", systemImage: "chart.bar.doc.horizontal")
                .font(.subheadline.bold())

            ForEach(budgets) { budget in
                let spent = allTransactions
                    .filter { tx in
                        guard tx.amount < 0,
                              tx.category == budget.category,
                              let d = tx.date else { return false }
                        return calendar.component(.year,  from: d) == year &&
                               calendar.component(.month, from: d) == month
                    }
                    .reduce(0) { $0 + abs($1.amount) }
                let ratio = budget.monthlyLimit > 0 ? min(spent / budget.monthlyLimit, 1.0) : 0
                let color: Color = ratio < 0.75 ? .ledgerPositive : ratio < 1.0 ? .orange : .ledgerNegative

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(budget.transactionCategory.displayName,
                              systemImage: budget.transactionCategory.icon)
                            .font(.caption)
                        Spacer()
                        Text(spent.asCurrency(code: currencyCode))
                            .font(Theme.monoCaption())
                            .foregroundStyle(color)
                        Text("/ \(budget.monthlyLimit.asCurrency(code: currencyCode))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(.systemFill))
                                .frame(height: 5)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color)
                                .frame(width: geo.size.width * ratio, height: 5)
                                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: ratio)
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
        .padding(Theme.s16)
        .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
    }

    // MARK: - Bot Pulse card

    private static let botSymbols = ["BTC", "ETH", "SOL"]

    @ViewBuilder
    private var botPulseCard: some View {
        let activeSignals = Self.botSymbols.compactMap { signalService.signals[$0] }

        if signalService.isFetching || !activeSignals.isEmpty {
            VStack(alignment: .leading, spacing: Theme.s12) {
                HStack {
                    Label("Bot Pulse", systemImage: "waveform.path.ecg")
                        .font(.subheadline.bold())
                    Spacer()
                    if signalService.isFetching {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.ledgerPositive)
                                .frame(width: 7, height: 7)
                            Text("Live")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if activeSignals.isEmpty {
                    Text("Syncing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeSignals, id: \.symbol) { sig in
                        botPulseRow(sig)
                        if sig.symbol != activeSignals.last?.symbol {
                            Divider()
                        }
                    }
                }
            }
            .padding(Theme.s16)
            .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
        }
    }

    private func botPulseRow(_ sig: QuantSignal) -> some View {
        HStack(spacing: Theme.s8) {
            Text(sig.symbol)
                .font(.subheadline.bold())
                .frame(width: 36, alignment: .leading)

            let posColor: Color = {
                switch sig.position {
                case "long":  return .ledgerPositive
                case "short": return .ledgerNegative
                default:      return Color(.secondaryLabel)
                }
            }()
            Text(sig.position.uppercased())
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(posColor.opacity(0.15), in: Capsule())
                .foregroundStyle(posColor)

            let zSign = sig.zScore >= 0 ? "+" : ""
            Text("z\(zSign)\(String(format: "%.2f", sig.zScore))")
                .font(Theme.monoCaption())
                .foregroundStyle(.secondary)

            if sig.socialSpike {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Spacer()

            if let ps = sig.paperSummary {
                Text("\(ps.nTrades)t")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(Int(ps.winRate * 100))%")
                    .font(.caption2.bold())
                    .foregroundStyle(ps.winRate >= 0.5 ? .ledgerPositive : .ledgerNegative)
            }
        }
    }

    // MARK: - Velocity alert banner

    @ViewBuilder
    private var velocityBannerCard: some View {
        VStack(alignment: .leading, spacing: Theme.s8) {
            HStack {
                Label("Spending Alert", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
                Spacer()
                Button {
                    withAnimation {
                        velocityDismissedDay = todayString()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(velocityAlerts) { alert in
                HStack(spacing: Theme.s8) {
                    Image(systemName: alert.category.icon)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("\(alert.category.displayName): on pace to spend \(Int((alert.ratio - 1) * 100))% more than usual this month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Theme.s16)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.radiusM))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).stroke(Color.orange.opacity(0.25), lineWidth: 1))
    }

    // MARK: - FI/RE card

    private var hasEnoughFireData: Bool {
        guard let oldest = allTransactions.first(where: { $0.date != nil })?.date,
              let threshold = Calendar.current.date(byAdding: .month, value: -3, to: .now)
        else { return false }
        return oldest <= threshold
    }

    private var annualExpenses: Double {
        let cal = Calendar.current
        guard let yearAgo = cal.date(byAdding: .year, value: -1, to: .now) else { return 0 }
        return allTransactions
            .filter { ($0.date ?? .distantPast) >= yearAgo && $0.amount < 0 }
            .reduce(0) { $0 + abs($1.amount) }
    }

    private var fireNumber: Double { annualExpenses * fireMultiplier }
    private var fireProgress: Double { fireNumber > 0 ? max(0, min(totalBalance / fireNumber, 1.0)) : 0 }

    private var projectedFIREDate: Date? {
        guard fireNumber > totalBalance, currentMonthSavings > 0 else { return nil }
        let months = Int((fireNumber - totalBalance) / currentMonthSavings)
        guard months > 0 else { return nil }
        return Calendar.current.date(byAdding: .month, value: months, to: .now)
    }

    @ViewBuilder
    private var fireCard: some View {
        if hasEnoughFireData && annualExpenses > 0 {
            VStack(alignment: .leading, spacing: Theme.s12) {
                HStack {
                    Label("FI/RE Number", systemImage: "flame.fill")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("\(Int(fireMultiplier))× expenses")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(totalBalance.asCurrency(code: currencyCode))
                        .font(Theme.monoSubhead())
                        .contentTransition(.numericText())
                    Text("of")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(fireNumber.asCurrency(code: currencyCode))
                        .font(Theme.monoSubhead())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(fireProgress * 100))%")
                        .font(Theme.monoSubhead().bold())
                        .foregroundStyle(fireProgress >= 1 ? .ledgerPositive : .ledgerAccent)
                        .contentTransition(.numericText())
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color(.systemFill)).frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(fireProgress >= 1 ? Color.ledgerPositive : Color.ledgerAccent)
                            .frame(width: geo.size.width * fireProgress, height: 8)
                            .animation(.spring(response: 0.8, dampingFraction: 0.8), value: fireProgress)
                    }
                }
                .frame(height: 8)

                if fireProgress >= 1 {
                    Text("Financially independent!")
                        .font(.caption).foregroundStyle(.ledgerPositive)
                } else if let date = projectedFIREDate {
                    Text("At current savings rate · est. \(date.formatted(.dateTime.month(.abbreviated).year()))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Add more months of data for a projection")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(Theme.s16)
            .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
        } else if !allTransactions.isEmpty {
            // Show a teaser so new users know the FI/RE card is coming.
            HStack(spacing: Theme.s12) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(Color.ledgerAccent.opacity(0.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text("FI/RE Tracker")
                        .font(.subheadline.bold())
                    Text("Available after 3 months of transactions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(Theme.s16)
            .background(Color.ledgerSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.radiusM))
        }
    }

    // MARK: - Empty state card (shown when no accounts exist)

    private var emptyStateCard: some View {
        Button { showingAddAccount = true } label: {
            HStack(spacing: Theme.s16) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.ledgerAccent)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Add your first account")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Track checking, savings, investments, and crypto in one place.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(Theme.s16)
            .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Month label helper for drill-through

    private func monthLabel(_ dc: DateComponents) -> String {
        guard let y = dc.year, let m = dc.month,
              let date = Calendar.current.date(from: DateComponents(year: y, month: m)) else {
            return "Transactions"
        }
        return date.formatted(.dateTime.month(.wide).year())
    }

    // "£12k", "¥1.2M", "$450" — compact labels for the Y axis; uses the user's currency symbol.
    private func compactCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 0
        let symbol = formatter.currencySymbol ?? "$"

        let abs  = Swift.abs(value)
        let sign = value < 0 ? "-" : ""
        switch abs {
        case 1_000_000...: return "\(sign)\(symbol)\(String(format: "%.1f", abs / 1_000_000))M"
        case 1_000...:     return "\(sign)\(symbol)\(String(format: "%.0f", abs / 1_000))k"
        default:           return "\(sign)\(symbol)\(String(format: "%.0f", abs))"
        }
    }
}

#Preview {
    DashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(PriceService())
        .environmentObject(QuantStatusService())
        .environmentObject(QuantSignalService())
}
