import SwiftUI
import CoreData

struct AddWatchlistItemView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var symbol    = ""
    @State private var name      = ""
    @State private var assetType = AssetType.stock

    @FocusState private var symbolFocused: Bool

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
        let item       = WatchlistItem(context: ctx)
        item.id        = UUID()
        item.symbol    = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        item.name      = name.trimmingCharacters(in: .whitespaces)
        item.assetType = assetType.rawValue
        item.addedAt   = .now
        try? ctx.save()
        HapticService.success()
        dismiss()
    }
}
