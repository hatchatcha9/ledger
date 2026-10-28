import SwiftUI

struct SubscriptionRadarView: View {
    let subscriptions: [DetectedSubscription]
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.dismiss) private var dismiss

    private var totalAnnual: Double {
        subscriptions.reduce(0) { $0 + $1.annualCost }
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Annual total header
                Section {
                    VStack(spacing: Theme.s8) {
                        Text(totalAnnual.asCurrency(code: currencyCode))
                            .font(Theme.monoLargeTitle())
                        Text("Estimated annual subscriptions")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(subscriptions.count) recurring charge\(subscriptions.count == 1 ? "" : "s") detected")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.s8)
                }

                // MARK: Subscription rows
                if subscriptions.isEmpty {
                    Section {
                        Label("No recurring charges detected yet. Add more transactions to improve detection.",
                              systemImage: "magnifyingglass")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Detected") {
                        ForEach(subscriptions) { sub in
                            subscriptionRow(sub)
                        }
                    }
                }

                // MARK: Disclaimer
                Section {
                    Text("Detection is based on repeated transactions with similar descriptions. Manual review recommended before cancelling anything.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Subscription Radar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func subscriptionRow(_ sub: DetectedSubscription) -> some View {
        HStack(spacing: Theme.s12) {
            Image(systemName: "repeat.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.ledgerAccent)
                .frame(width: 36, height: 36)
                .background(Color.ledgerAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusS))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.s4) {
                    Text(sub.name)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    if let change = sub.priceChange, change > 0 {
                        Label(String(format: "+%.2f", change), systemImage: "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.ledgerNegative.opacity(0.12), in: Capsule())
                            .foregroundStyle(.ledgerNegative)
                    }
                }
                HStack(spacing: Theme.s4) {
                    Text(sub.frequency)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("last \(sub.lastCharged, style: .date)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("\(sub.occurrences) charges")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(sub.avgAmount.asCurrency(code: currencyCode))
                    .font(Theme.monoCaption().bold())
                Text("\(sub.annualCost.asCurrency(code: currencyCode))/yr")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Theme.s4)
    }
}

#Preview {
    SubscriptionRadarView(subscriptions: [
        DetectedSubscription(name: "Netflix", avgAmount: 15.49, annualCost: 185.88,
                             frequency: "Monthly", lastCharged: .now, priceChange: 2.0, occurrences: 8),
        DetectedSubscription(name: "Spotify", avgAmount: 10.99, annualCost: 131.88,
                             frequency: "Monthly", lastCharged: .now, priceChange: nil, occurrences: 6),
    ])
}
