import SwiftUI

struct AssetDetailView: View {
    @ObservedObject var asset: Asset
    @EnvironmentObject private var priceService: PriceService
    @Environment(\.managedObjectContext) private var ctx
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddAlert    = false
    @State private var editingAlert: PriceAlert? = nil

    private var activeAlerts: [PriceAlert] {
        let req = PriceAlert.fetchRequest()
        req.predicate = NSPredicate(format: "symbol == %@ AND isActive == YES", asset.wrappedSymbol)
        req.sortDescriptors = [NSSortDescriptor(keyPath: \PriceAlert.createdAt, ascending: false)]
        return (try? ctx.fetch(req)) ?? []
    }

    private var currentPrice: Double? { priceService.prices[asset.wrappedSymbol] }
    private var dailyChange: Double?  { priceService.changes[asset.wrappedSymbol] }

    private var currentValue: Double {
        (currentPrice ?? asset.avgCost) * asset.quantity
    }
    private var unrealizedPnL: Double {
        guard let price = currentPrice else { return 0 }
        return asset.unrealisedPnL(currentPrice: price)
    }
    private var unrealizedPnLPct: Double {
        guard let price = currentPrice else { return 0 }
        return asset.unrealisedPnLPercent(currentPrice: price)
    }
    private var hasCurrent: Bool { currentPrice != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.s16) {

                // MARK: Hero — asset icon + name
                VStack(spacing: Theme.s8) {
                    Image(systemName: asset.assetKind.icon)
                        .font(.system(size: 40))
                        .foregroundStyle(Color.ledgerAccent)
                        .frame(width: 72, height: 72)
                        .background(Color.ledgerAccent.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: Theme.radiusM))

                    Text(asset.wrappedSymbol)
                        .font(.title2.bold())

                    if !asset.wrappedName.isEmpty && asset.wrappedName != asset.wrappedSymbol {
                        Text(asset.wrappedName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(asset.assetKind.displayName)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color.ledgerAccent.opacity(0.1), in: Capsule())
                        .foregroundStyle(Color.ledgerAccent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.s8)

                // MARK: P&L card
                VStack(spacing: Theme.s12) {
                    Text("Unrealized P&L")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if hasCurrent {
                        Text((unrealizedPnL >= 0 ? "+" : "") + unrealizedPnL.asCurrency(code: currencyCode))
                            .font(Theme.monoTitle2())
                            .foregroundStyle(Color.changeColor(for: unrealizedPnL))

                        HStack(spacing: Theme.s8) {
                            Label(unrealizedPnLPct.asChangePercent(), systemImage:
                                    unrealizedPnL >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.subheadline.bold())
                                .foregroundStyle(Color.changeColor(for: unrealizedPnL))

                            if let dc = dailyChange {
                                Text("·")
                                    .foregroundStyle(.quaternary)
                                Text("Today: \(dc.asChangePercent())")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.changeColor(for: dc))
                            }
                        }
                    } else {
                        Text("—")
                            .font(Theme.monoTitle2())
                            .foregroundStyle(.secondary)
                        Text("No live price")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(Theme.s16)
                .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))

                // MARK: Price Alerts
                let alerts = activeAlerts
                VStack(alignment: .leading, spacing: Theme.s12) {
                    HStack {
                        Label("Price Alerts", systemImage: "bell.badge")
                            .font(.subheadline.bold())
                        Spacer()
                        Button {
                            showingAddAlert = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.ledgerAccent)
                        }
                    }

                    if alerts.isEmpty {
                        Text("No active alerts. Tap + to add one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(alerts) { alert in
                            HStack {
                                Image(systemName: alert.alertCondition.icon)
                                    .foregroundStyle(Color.ledgerAccent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(alert.alertCondition.displayName) \(alert.targetPrice.asCurrency(code: currencyCode))")
                                        .font(.subheadline)
                                    if !alert.wrappedNote.isEmpty {
                                        Text(alert.wrappedNote)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button {
                                    editingAlert = alert
                                } label: {
                                    Image(systemName: "pencil.circle")
                                        .foregroundStyle(.secondary)
                                }
                                Button(role: .destructive) {
                                    alert.isActive = false
                                    try? ctx.save()
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(.ledgerNegative)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Theme.s16)
                .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))

                // MARK: Metrics grid
                VStack(spacing: 0) {
                    metricRow(
                        label: "Current Price",
                        value: currentPrice.map { $0.asCurrency(code: currencyCode) } ?? "—",
                        valueColor: .primary
                    )
                    Divider().padding(.leading, Theme.s16)
                    metricRow(
                        label: "Avg Cost / Unit",
                        value: asset.avgCost.asCurrency(code: currencyCode),
                        valueColor: .primary
                    )
                    Divider().padding(.leading, Theme.s16)
                    metricRow(
                        label: "Quantity",
                        value: String(format: "%g", asset.quantity),
                        valueColor: .primary
                    )
                    Divider().padding(.leading, Theme.s16)
                    metricRow(
                        label: "Total Cost Basis",
                        value: asset.costBasis.asCurrency(code: currencyCode),
                        valueColor: .primary
                    )
                    Divider().padding(.leading, Theme.s16)
                    metricRow(
                        label: "Current Value",
                        value: currentValue.asCurrency(code: currencyCode),
                        valueColor: hasCurrent ? Color.changeColor(for: unrealizedPnL) : .primary
                    )
                }
                .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
            }
            .padding(Theme.s16)
        }
        .navigationTitle(asset.wrappedSymbol)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.ledgerGrouped)
        .sheet(isPresented: $showingAddAlert) {
            AddEditPriceAlertView(symbol: asset.wrappedSymbol)
                .environment(\.managedObjectContext, ctx)
        }
        .sheet(item: $editingAlert) { alert in
            AddEditPriceAlertView(symbol: asset.wrappedSymbol, alert: alert)
                .environment(\.managedObjectContext, ctx)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if priceService.isLoading {
                    ProgressView()
                } else {
                    Button {
                        Task { await priceService.refresh(assets: [asset]) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private func metricRow(label: String, value: String, valueColor: Color) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(Theme.monoSubhead())
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, Theme.s16)
        .padding(.vertical, Theme.s12)
    }
}

#Preview {
    let ctx = PersistenceController.preview.container.viewContext
    let asset = try! ctx.fetch(Asset.fetchRequest()).first!
    return NavigationStack {
        AssetDetailView(asset: asset)
    }
    .environment(\.managedObjectContext, ctx)
    .environmentObject(PriceService())
}
