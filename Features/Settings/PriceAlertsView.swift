import SwiftUI
import CoreData

struct PriceAlertsView: View {
    @Environment(\.managedObjectContext) private var ctx

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)],
        animation: .default
    ) private var alerts: FetchedResults<PriceAlert>

    private var activeAlerts:    [PriceAlert] { alerts.filter { $0.isActive } }
    private var triggeredAlerts: [PriceAlert] { alerts.filter { !$0.isActive } }

    var body: some View {
        List {
            if alerts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bell.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.quaternary)
                    Text("No price alerts set")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Tap + in an asset's detail view to add an alert.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .listRowBackground(Color.clear)
            } else {
                if !activeAlerts.isEmpty {
                    Section("Active") {
                        ForEach(activeAlerts) { alert in
                            AlertRow(alert: alert)
                        }
                        .onDelete { offsets in
                            offsets.map { activeAlerts[$0] }.forEach { $0.isActive = false }
                            try? ctx.save()
                        }
                    }
                }

                if !triggeredAlerts.isEmpty {
                    Section("Triggered") {
                        ForEach(triggeredAlerts) { alert in
                            AlertRow(alert: alert)
                                .opacity(0.5)
                        }
                        .onDelete { offsets in
                            offsets.map { triggeredAlerts[$0] }.forEach(ctx.delete)
                            try? ctx.save()
                        }
                    }
                }
            }
        }
        .navigationTitle("Price Alerts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !triggeredAlerts.isEmpty {
                    Button("Clear History") {
                        triggeredAlerts.forEach(ctx.delete)
                        try? ctx.save()
                    }
                    .foregroundStyle(.ledgerNegative)
                }
            }
        }
    }
}

// MARK: - Alert Row

private struct AlertRow: View {
    @ObservedObject var alert: PriceAlert

    var body: some View {
        HStack(spacing: Theme.s12) {
            Image(systemName: alert.alertCondition.icon)
                .font(.body)
                .foregroundStyle(Color.ledgerAccent)
                .frame(width: 36, height: 36)
                .background(Color.ledgerAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusS))

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.wrappedSymbol).font(.body.bold())
                Text("\(alert.alertCondition.displayName) \(alert.targetPrice.asCurrency())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !alert.wrappedNote.isEmpty {
                    Text(alert.wrappedNote)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if alert.isActive {
                Image(systemName: "bell.fill")
                    .font(.caption)
                    .foregroundStyle(Color.ledgerAccent.opacity(0.7))
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.ledgerPositive)
            }
        }
        .padding(.vertical, Theme.s4)
    }
}

#Preview {
    NavigationStack {
        PriceAlertsView()
            .environment(\.managedObjectContext,
                         PersistenceController.preview.container.viewContext)
    }
}
