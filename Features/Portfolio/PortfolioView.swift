import SwiftUI
import CoreData
import Charts

struct PortfolioView: View {
    @Environment(\.managedObjectContext) private var ctx
    @EnvironmentObject private var priceService: PriceService
    @EnvironmentObject private var quantStatus: QuantStatusService

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.symbol)],
        animation: .default
    ) private var assets: FetchedResults<Asset>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.addedAt, order: .reverse)],
        animation: .default
    ) private var watchlist: FetchedResults<WatchlistItem>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.name)],
        animation: .default
    ) private var accounts: FetchedResults<Account>

    @EnvironmentObject private var sentimentService: SentimentService

    @AppStorage("currencyCode") private var currencyCode = "USD"
    @State private var showingAddWatchlist   = false
    @State private var showingAddAsset       = false
    @State private var quickAddAccount: Account? = nil
    @State private var editingWatchlistItem: WatchlistItem? = nil

    // MARK: - Computed totals

    private var totalValue: Double {
        assets.reduce(0) { sum, asset in
            let price = priceService.prices[asset.wrappedSymbol] ?? asset.avgCost
            return sum + price * asset.quantity
        }
    }

    private var totalCostBasis: Double { assets.reduce(0) { $0 + $1.costBasis } }

    private var accountCurrencies: [String] {
        Array(Set(accounts.map(\.wrappedCurrency)))
    }

    private var totalUnrealizedPnL: Double { totalValue - totalCostBasis }

    private var totalUnrealizedPct: Double {
        guard totalCostBasis > 0 else { return 0 }
        return (totalUnrealizedPnL / totalCostBasis) * 100
    }

    // Allocation by AssetType for the donut chart.
    private struct AllocationSlice: Identifiable {
        var id: String { type.rawValue }
        let type: AssetType
        let value: Double
    }

    private var allocationSlices: [AllocationSlice] {
        var totals = [AssetType: Double]()
        for asset in assets {
            let price = priceService.prices[asset.wrappedSymbol] ?? asset.avgCost
            totals[asset.assetKind, default: 0] += price * asset.quantity
        }
        return totals
            .map { AllocationSlice(type: $0.key, value: $0.value) }
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
    }

    // Weighted-average 24 h change across all priced assets.
    private var portfolioChange: Double? {
        let priced = assets.filter { priceService.prices[$0.wrappedSymbol] != nil }
        guard !priced.isEmpty else { return nil }
        let totalPricedValue = priced.reduce(0) {
            $0 + priceService.prices[$1.wrappedSymbol]! * $1.quantity
        }
        guard totalPricedValue > 0 else { return nil }
        return priced.reduce(0) { sum, asset in
            let price  = priceService.prices[asset.wrappedSymbol]!
            let weight = (price * asset.quantity) / totalPricedValue
            return sum + (priceService.changes[asset.wrappedSymbol] ?? 0) * weight
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // MARK: Portfolio value tile
                Section {
                    portfolioValueTile
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                // MARK: Allocation chart
                if allocationSlices.count > 1 {
                    Section {
                        allocationChart
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                // MARK: Quant bots teaser
                if quantStatus.status != nil || quantStatus.isFetching {
                    Section {
                        QuantBotCard(onTapOpenBots: {
                            NotificationCenter.default.post(name: .openBotsTab, object: nil)
                        })
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                // MARK: Assets
                Section {
                    ForEach(assets) { asset in
                        NavigationLink {
                            AssetDetailView(asset: asset)
                                .environmentObject(priceService)
                                .environmentObject(sentimentService)
                        } label: {
                            AssetRow(
                                asset: asset,
                                currentPrice:  priceService.prices[asset.wrappedSymbol],
                                dailyChange:   priceService.changes[asset.wrappedSymbol],
                                currencyCode:  currencyCode,
                                isLoading:     priceService.isLoading,
                                sentimentData: sentimentService.sentiment[asset.wrappedSymbol]
                            )
                        }
                    }
                } header: {
                    HStack {
                        Text("Holdings")
                        Spacer()
                        Button {
                            if let first = accounts.first(where: { !$0.assetsArray.isEmpty }) {
                                quickAddAccount = first
                            } else {
                                quickAddAccount = accounts.first
                            }
                            showingAddAsset = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.ledgerAccent)
                        }
                        .buttonStyle(.plain)
                        .disabled(accounts.isEmpty)
                    }
                } footer: {
                    if !watchlist.isEmpty { EmptyView() } else { updatedFooter }
                }

                // Empty holdings placeholder — inside the list so QuantBotCard stays visible
                if assets.isEmpty {
                    Section {
                        Label("No assets yet — add one via an account.", systemImage: "chart.pie")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                            .listRowBackground(Color.clear)
                    }
                }

                // MARK: Watchlist
                Section {
                    if watchlist.isEmpty {
                        Button {
                            showingAddWatchlist = true
                        } label: {
                            Label("Add symbol to watch", systemImage: "plus")
                                .font(.subheadline)
                                .foregroundStyle(Color.ledgerAccent)
                        }
                    } else {
                        ForEach(watchlist) { item in
                            WatchlistRow(
                                item: item,
                                currentPrice:  priceService.prices[item.wrappedSymbol],
                                dailyChange:   priceService.changes[item.wrappedSymbol],
                                currencyCode:  currencyCode,
                                isLoading:     priceService.isLoading,
                                sentimentData: sentimentService.sentiment[item.wrappedSymbol]
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { editingWatchlistItem = item }
                        }
                        .onDelete(perform: deleteWatchlistItems)
                    }
                } header: {
                    HStack {
                        Text("Watchlist")
                        Spacer()
                        Button {
                            showingAddWatchlist = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.ledgerAccent)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    updatedFooter
                }
            }
            .navigationTitle("Portfolio")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if priceService.isLoading {
                        ProgressView()
                    } else {
                        Button {
                            Task { await priceService.refresh(assets: Array(assets), watchlist: Array(watchlist), currencies: accountCurrencies) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable {
                await priceService.refresh(assets: Array(assets), watchlist: Array(watchlist), currencies: accountCurrencies)
                HapticService.impact(.soft)
            }
            .task(id: (assets.map(\.wrappedSymbol) + watchlist.map(\.wrappedSymbol)).joined()) {
                await priceService.refresh(assets: Array(assets), watchlist: Array(watchlist), currencies: accountCurrencies)
            }
            .task {
                await quantStatus.fetch()
            }
            .task(id: (assets.map(\.wrappedSymbol) + watchlist.map(\.wrappedSymbol)).joined() + "sentiment") {
                let allTickers = assets.map(\.wrappedSymbol) + watchlist.map(\.wrappedSymbol)
                await sentimentService.fetch(symbols: allTickers)
            }
            .sheet(isPresented: $showingAddWatchlist) {
                AddWatchlistItemView()
                    .environment(\.managedObjectContext, ctx)
            }
            .sheet(item: $editingWatchlistItem) { item in
                EditWatchlistItemView(item: item)
                    .environment(\.managedObjectContext, ctx)
            }
            .sheet(isPresented: $showingAddAsset) {
                if let acct = quickAddAccount ?? accounts.first {
                    QuickAddPositionView(accounts: Array(accounts), selectedAccount: acct)
                        .environment(\.managedObjectContext, ctx)
                }
            }
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var portfolioValueTile: some View {
        let change = portfolioChange
        VStack(spacing: Theme.s8) {
            StatTile(
                label: "Portfolio Value",
                value: totalValue > 0
                    ? totalValue.asCurrency(code: currencyCode)
                    : (priceService.isLoading && !assets.isEmpty ? "Updating…" : "—"),
                change: change.map { $0.asChangePercent() },
                changePositive: change.map { $0 >= 0 },
                icon: "chart.pie.fill"
            )

            if totalCostBasis > 0 {
                HStack(spacing: Theme.s24) {
                    pnlPill(
                        label: "Cost Basis",
                        value: totalCostBasis.asCurrency(code: currencyCode),
                        color: .secondary
                    )
                    pnlPill(
                        label: "Unrealized P&L",
                        value: (totalUnrealizedPnL >= 0 ? "+" : "") + totalUnrealizedPnL.asCurrency(code: currencyCode),
                        color: Color.changeColor(for: totalUnrealizedPnL)
                    )
                    pnlPill(
                        label: "Return",
                        value: totalUnrealizedPct.asChangePercent(),
                        color: Color.changeColor(for: totalUnrealizedPct)
                    )
                }
                .padding(.horizontal, Theme.s16)
                .padding(.bottom, Theme.s8)
            }
        }
    }

    private func pnlPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.monoCaption().bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var allocationChart: some View {
        let slices = allocationSlices
        let total  = slices.reduce(0) { $0 + $1.value }
        let colors: [Color] = [.ledgerAccent, .ledgerPositive, .orange, .purple, .pink,
                               .cyan, .yellow, .indigo]

        VStack(alignment: .leading, spacing: Theme.s8) {
            Text("Allocation")
                .font(.subheadline.bold())
                .padding(.horizontal, Theme.s16)
                .padding(.top, Theme.s12)

            HStack(spacing: Theme.s16) {
                if #available(iOS 17, *) {
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Value", slice.value),
                            innerRadius: .ratio(0.55),
                            angularInset: 2
                        )
                        .foregroundStyle(by: .value("Type", slice.type.displayName))
                        .cornerRadius(4)
                    }
                    .chartForegroundStyleScale(
                        domain: slices.map { $0.type.displayName },
                        range:  colors.prefix(slices.count).map { $0 }
                    )
                    .chartLegend(.hidden)
                    .frame(width: 110, height: 110)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(slices.enumerated()), id: \.offset) { i, slice in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(colors[i % colors.count])
                                .frame(width: 8, height: 8)
                            Text(slice.type.displayName)
                                .font(.caption)
                            Spacer()
                            Text(total > 0 ? "\(Int((slice.value / total) * 100))%" : "—")
                                .font(.system(.caption, design: .monospaced).bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.s16)
            .padding(.bottom, Theme.s12)
        }
        .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
        .padding(.horizontal, Theme.s16)
        .padding(.vertical, Theme.s4)
    }

    private func deleteWatchlistItems(at offsets: IndexSet) {
        HapticService.impact(.rigid)
        offsets.map { watchlist[$0] }.forEach(ctx.delete)
        try? ctx.save()
    }

    @ViewBuilder
    private var updatedFooter: some View {
        if let error = priceService.fetchError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.ledgerNegative)
        } else if let ts = priceService.lastUpdated {
            Text("Updated \(ts, style: .time)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Watchlist Row

private struct WatchlistRow: View {
    @ObservedObject var item: WatchlistItem
    let currentPrice:  Double?
    let dailyChange:   Double?
    let currencyCode:  String
    var isLoading:     Bool = false
    var sentimentData: SentimentData? = nil

    var body: some View {
        HStack(spacing: Theme.s12) {
            Image(systemName: item.assetKind.icon)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 36, height: 36)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusS))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.wrappedSymbol).font(.body.bold())
                Text(item.wrappedName.isEmpty ? item.assetKind.displayName : item.wrappedName)
                    .font(.caption).foregroundStyle(.secondary)
                SentimentBadge(data: sentimentData)
                if !item.wrappedThesis.isEmpty {
                    Text(item.wrappedThesis)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let price = currentPrice {
                    Text(price.asCurrency(code: currencyCode))
                        .font(Theme.monoBody())
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: price)
                    if let dc = dailyChange {
                        Text(dc.asChangePercent())
                            .font(.caption)
                            .foregroundStyle(Color.changeColor(for: dc))
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: dc)
                    }
                    // Target price indicator
                    if item.hasTargetPrice {
                        let gap = (item.targetPriceValue - price) / price * 100
                        Text("\(gap >= 0 ? "+" : "")\(String(format: "%.1f", gap))% to target")
                            .font(.caption2)
                            .foregroundStyle(gap >= 0 ? Color.ledgerPositive : Color.ledgerNegative)
                    }
                } else if isLoading {
                    ShimmerView(height: 16, cornerRadius: 4).frame(width: 72)
                    ShimmerView(height: 11, cornerRadius: 3).frame(width: 44)
                } else {
                    Text("—").font(Theme.monoBody()).foregroundStyle(.secondary)
                    if item.hasTargetPrice {
                        Text("Target: \(item.targetPriceValue.asCurrency(code: currencyCode))")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("Watching").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, Theme.s4)
    }
}

// MARK: - Asset Row

private struct AssetRow: View {
    @ObservedObject var asset: Asset
    let currentPrice:  Double?
    let dailyChange:   Double?
    var currencyCode:  String = "USD"
    var isLoading:     Bool = false
    var sentimentData: SentimentData? = nil

    var body: some View {
        HStack(spacing: Theme.s12) {
            // Icon badge
            Image(systemName: asset.assetKind.icon)
                .font(.title3)
                .foregroundStyle(Color.ledgerAccent)
                .frame(width: 36, height: 36)
                .background(Color.ledgerAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusS))

            // Symbol + name + sentiment
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.wrappedSymbol)
                    .font(.body.bold())
                Text(asset.wrappedName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SentimentBadge(data: sentimentData)
            }

            Spacer()

            // Price + P&L
            VStack(alignment: .trailing, spacing: 2) {
                if let price = currentPrice {
                    Text(price.asCurrency(code: currencyCode))
                        .font(Theme.monoBody())
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: price)

                    let pnl = asset.unrealisedPnLPercent(currentPrice: price)
                    HStack(spacing: 2) {
                        if let dc = dailyChange {
                            Text(dc.asChangePercent())
                                .foregroundStyle(Color.changeColor(for: dc))
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: dc)
                        }
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(pnl.asChangePercent())
                            .foregroundStyle(Color.changeColor(for: pnl))
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: pnl)
                    }
                    .font(.caption)
                } else if isLoading {
                    ShimmerView(height: 16, cornerRadius: 4).frame(width: 80)
                    ShimmerView(height: 11, cornerRadius: 3).frame(width: 56)
                } else {
                    Text("—")
                        .font(Theme.monoBody())
                        .foregroundStyle(.secondary)
                    Text("qty \(asset.quantity, specifier: "%g")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, Theme.s4)
    }
}

#Preview {
    PortfolioView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(PriceService())
        .environmentObject(QuantStatusService())
        .environmentObject(SentimentService())
}
