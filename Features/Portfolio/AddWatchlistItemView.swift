import SwiftUI
import CoreData

struct AddWatchlistItemView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var symbol          = ""
    @State private var name            = ""
    @State private var assetType       = AssetType.stock
    @State private var thesisText      = ""
    @State private var targetPriceText = ""

    @FocusState private var symbolFocused: Bool

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
                            .focused($symbolFocused)
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
                } footer: {
                    Text("Watchlist items are tracked at live market prices but not counted in your portfolio value.")
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
            .navigationTitle("Add to Watchlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { save() }
                        .bold()
                        .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { symbolFocused = true }
        }
    }

    private func save() {
        let item          = WatchlistItem(context: ctx)
        item.id           = UUID()
        item.symbol       = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        item.name         = name.trimmingCharacters(in: .whitespaces)
        item.assetType    = assetType.rawValue
        item.addedAt      = .now
        item.thesis       = thesisText.isEmpty ? nil : thesisText.trimmingCharacters(in: .whitespacesAndNewlines)
        item.targetPrice  = targetPrice ?? 0
        try? ctx.save()
        HapticService.success()
        dismiss()
    }
}
