import SwiftUI
import CoreData

struct EditWatchlistItemView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    let item: WatchlistItem

    @State private var symbol          = ""
    @State private var name            = ""
    @State private var assetType       = AssetType.stock
    @State private var thesisText      = ""
    @State private var targetPriceText = ""

    private var targetPrice: Double? {
        guard !targetPriceText.isEmpty else { return nil }
        return Double(targetPriceText.replacingOccurrences(of: ",", with: ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Symbol")
                        TextField("e.g. AAPL, BTC", text: $symbol)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                    }
                    HStack {
                        Text("Name")
                        TextField("Optional display name", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Type", selection: $assetType) {
                        ForEach(AssetType.allCases) {
                            Label($0.displayName, systemImage: $0.icon).tag($0)
                        }
                    }
                }

                Section {
                    TextField("Why are you watching this? (optional)", text: $thesisText, axis: .vertical)
                        .lineLimit(2...5)
                    HStack {
                        Text("Target Price")
                        TextField("0.00", text: $targetPriceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Investment Thesis")
                } footer: {
                    Text("Your thesis and target price are private notes to help you stay disciplined.")
                }
            }
            .navigationTitle("Edit Watchlist Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { preload() }
        }
    }

    private func preload() {
        symbol          = item.wrappedSymbol
        name            = item.wrappedName
        assetType       = AssetType(rawValue: item.assetType ?? "") ?? .stock
        thesisText      = item.wrappedThesis
        targetPriceText = item.targetPriceValue > 0 ? String(format: "%.2f", item.targetPriceValue) : ""
    }

    private func save() {
        item.symbol      = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        item.name        = name.trimmingCharacters(in: .whitespaces)
        item.assetType   = assetType.rawValue
        item.thesis      = thesisText.isEmpty ? nil : thesisText.trimmingCharacters(in: .whitespacesAndNewlines)
        item.targetPrice = targetPrice ?? 0
        try? ctx.save()
        HapticService.success()
        dismiss()
    }
}
