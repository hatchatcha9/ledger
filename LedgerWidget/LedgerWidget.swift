import WidgetKit
import SwiftUI
import CoreData

// MARK: - Compat helper

private extension View {
    @ViewBuilder
    func widgetBackground(_ color: Color) -> some View {
        if #available(iOS 17, *) {
            self.containerBackground(color, for: .widget)
        } else {
            self.background(color)
        }
    }
}

// MARK: - App Group suite name
// Set this to match the App Group you configure in Xcode → Signing & Capabilities
// for BOTH the main app target and this widget extension (e.g. "group.com.you.ledger").
// The app must also write its CoreData store URL and currencyCode to this suite.
private let kAppGroupID = "group.ledger"

// MARK: - Timeline entry

struct LedgerEntry: TimelineEntry {
    let date:         Date
    let netWorth:     Double
    let currencyCode: String
    let topAssets:    [AssetSnapshot]

    struct AssetSnapshot: Identifiable {
        let id     = UUID()
        let symbol: String
        let value:  Double
    }
}

// MARK: - Provider

struct LedgerProvider: TimelineProvider {
    func placeholder(in context: Context) -> LedgerEntry {
        LedgerEntry(date: .now, netWorth: 15_650, currencyCode: "USD", topAssets: [
            .init(symbol: "BTC",  value: 3_250),
            .init(symbol: "AAPL", value: 1_820),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (LedgerEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LedgerEntry>) -> Void) {
        let entry    = readEntry()
        let nextDate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? Date(timeIntervalSinceNow: 1800)
        completion(Timeline(entries: [entry], policy: .after(nextDate)))
    }

    // MARK: - Read from CoreData + UserDefaults (shared App Group)

    private func readEntry() -> LedgerEntry {
        // Currency from shared UserDefaults.
        let shared   = UserDefaults(suiteName: kAppGroupID) ?? .standard
        let code     = shared.string(forKey: "currencyCode") ?? "USD"

        // CoreData — reads from the same SQLite store as the main app via App Group container.
        let container = makePersistentContainer()
        let ctx       = container.viewContext

        // Load cached FX rates written by PriceService on last refresh.
        var cachedFXRates: [String: Double] = [:]
        if let data = shared.data(forKey: "cachedFXRates"),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            cachedFXRates = decoded
        }

        let accountReq         = NSFetchRequest<Account>(entityName: "Account")
        let accounts           = (try? ctx.fetch(accountReq)) ?? []
        let netWorth           = accounts.reduce(0.0) { sum, acc in
            let currency = acc.currency ?? "USD"
            let rate = currency == "USD" ? 1.0 : (cachedFXRates[currency] ?? 1.0)
            return sum + acc.balance * rate
        }

        // Load cached market prices written by PriceService on last refresh.
        var cachedPrices: [String: Double] = [:]
        if let data = shared.data(forKey: "cachedPrices"),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            cachedPrices = decoded
        }

        let assetReq           = NSFetchRequest<Asset>(entityName: "Asset")
        let topAssets          = ((try? ctx.fetch(assetReq)) ?? [])
            .map { asset -> (Asset, Double) in
                let price = cachedPrices[asset.wrappedSymbol] ?? asset.avgCost
                return (asset, price * asset.quantity)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map { LedgerEntry.AssetSnapshot(symbol: $0.0.wrappedSymbol, value: $0.1) }

        return LedgerEntry(date: .now, netWorth: netWorth, currencyCode: code,
                           topAssets: Array(topAssets))
    }

    // Points the CoreData stack at the shared App Group container URL.
    private func makePersistentContainer() -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "Ledger")
        if let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: kAppGroupID)?
            .appendingPathComponent("Ledger.sqlite") {
            let desc = NSPersistentStoreDescription(url: url)
            container.persistentStoreDescriptions = [desc]
        }
        container.loadPersistentStores { _, _ in }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }
}

// MARK: - Entry view (family-aware)

struct LedgerWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LedgerEntry

    var body: some View {
        switch family {
        case .systemMedium: MediumWidgetView(entry: entry)
        default:            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small widget view

struct SmallWidgetView: View {
    let entry: LedgerEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.ledgerAccent)
                Text("LEDGER")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .kerning(1)
            }

            Spacer()

            Text("Net Worth")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(entry.netWorth.asCurrency(code: entry.currencyCode))
                .font(.system(.title3, design: .monospaced).bold())
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(entry.date, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetBackground(Color(.systemBackground))
    }
}

// MARK: - Medium widget view

struct MediumWidgetView: View {
    let entry: LedgerEntry

    var body: some View {
        HStack(spacing: 0) {
            // Left — net worth
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.ledgerAccent)
                    Text("LEDGER")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .kerning(1)
                }
                Spacer()
                Text("Net Worth")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.netWorth.asCurrency(code: entry.currencyCode))
                    .font(.system(.title3, design: .monospaced).bold())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(entry.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().padding(.vertical, 12)

            // Right — top holdings
            VStack(alignment: .leading, spacing: 6) {
                Text("Top Holdings")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                if entry.topAssets.isEmpty {
                    Text("No assets")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(entry.topAssets) { a in
                        HStack {
                            Text(a.symbol)
                                .font(.caption2.bold())
                                .lineLimit(1)
                            Spacer()
                            Text(a.value.asCurrency(code: entry.currencyCode))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetBackground(Color(.systemBackground))
    }
}

// MARK: - Widget bundle

struct LedgerWidget: Widget {
    let kind = "LedgerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LedgerProvider()) { entry in
            LedgerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Ledger")
        .description("Your net worth and top holdings.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct LedgerWidgetBundle: WidgetBundle {
    var body: some Widget { LedgerWidget() }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    LedgerWidget()
} timeline: {
    LedgerEntry(date: .now, netWorth: 15_650, currencyCode: "USD", topAssets: [])
}

#Preview(as: .systemMedium) {
    LedgerWidget()
} timeline: {
    LedgerEntry(date: .now, netWorth: 15_650, currencyCode: "USD", topAssets: [
        .init(symbol: "BTC",  value: 3_250),
        .init(symbol: "AAPL", value: 1_820),
        .init(symbol: "ETH",  value: 940),
    ])
}
