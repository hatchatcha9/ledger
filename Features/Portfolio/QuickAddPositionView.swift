import SwiftUI
import CoreData

struct QuickAddPositionView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    let accounts: [Account]
    @State var selectedAccount: Account

    @State private var symbol      = ""
    @State private var name        = ""
    @State private var assetType   = AssetType.stock
    @State private var quantityText = ""
    @State private var avgCostText  = ""

    @FocusState private var symbolFocused: Bool

    private var quantity: Double { Double(quantityText) ?? 0 }
    private var avgCost: Double  { Double(avgCostText.replacingOccurrences(of: ",", with: "")) ?? 0 }
    private var canSave: Bool    { !symbol.trimmingCharacters(in: .whitespaces).isEmpty && quantity > 0 && avgCost > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    Picker("Account", selection: $selectedAccount) {
                        ForEach(accounts) { acct in
                            Text(acct.wrappedName).tag(acct)
                        }
                    }
                }

                Section("Position") {
                    HStack {
                        Text("Symbol")
                        TextField("e.g. AAPL, BTC", text: $symbol)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                            .focused($symbolFocused)
                    }
                    HStack {
                        Text("Name")
                        TextField("Optional", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Type", selection: $assetType) {
                        ForEach(AssetType.allCases) {
                            Label($0.displayName, systemImage: $0.icon).tag($0)
                        }
                    }
                }

                Section("Purchase Details") {
                    HStack {
                        Text("Quantity")
                        TextField("0", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Avg Cost")
                        TextField("0.00", text: $avgCostText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if quantity > 0 && avgCost > 0 {
                        LabeledContent("Cost Basis", value: (quantity * avgCost).asCurrency(code: selectedAccount.wrappedCurrency))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add Position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .bold()
                        .disabled(!canSave)
                }
            }
            .onAppear { symbolFocused = true }
        }
    }

    private func save() {
        let asset        = Asset(context: ctx)
        asset.id         = UUID()
        asset.symbol     = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        asset.name       = name.trimmingCharacters(in: .whitespaces)
        asset.assetType  = assetType.rawValue
        asset.quantity   = quantity
        asset.avgCost    = avgCost
        asset.account    = selectedAccount
        try? ctx.save()
        HapticService.success()
        dismiss()
    }
}
