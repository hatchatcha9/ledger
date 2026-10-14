import SwiftUI

struct AddEditAssetView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    let account: Account
    var asset: Asset? = nil   // nil → add mode

    @State private var symbol = ""
    @State private var assetName = ""
    @State private var assetType: AssetType = .crypto
    @State private var quantityText = ""
    @State private var avgCostText = ""
    @FocusState private var symbolFocused: Bool
    @FocusState private var numericFocused: Bool

    private var isEditing: Bool { asset != nil }

    private var parsedQuantity: Double? {
        Double(quantityText.replacingOccurrences(of: ",", with: ""))
    }

    private var parsedAvgCost: Double? {
        Double(avgCostText.replacingOccurrences(of: ",", with: ""))
    }

    private var costBasis: Double? {
        guard let q = parsedQuantity, let c = parsedAvgCost else { return nil }
        return q * c
    }

    private var canSave: Bool {
        !symbol.trimmingCharacters(in: .whitespaces).isEmpty
            && (parsedQuantity ?? 0) > 0
            && (parsedAvgCost ?? -1) >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Identity
                Section("Asset Details") {
                    TextField("Symbol, e.g. BTC", text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($symbolFocused)
                        .onChange(of: symbol) { new in
                            symbol = new.uppercased()
                        }

                    TextField("Name, e.g. Bitcoin", text: $assetName)
                        .textInputAutocapitalization(.words)

                    Picker("Type", selection: $assetType) {
                        ForEach(AssetType.allCases) { t in
                            Label(t.displayName, systemImage: t.icon).tag(t)
                        }
                    }
                }

                // MARK: Position
                Section {
                    HStack {
                        Text("Qty")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)
                        TextField("0.00000000", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .font(.system(.body, design: .monospaced))
                            .focused($numericFocused)
                    }

                    HStack {
                        Text(account.wrappedCurrency)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)
                        TextField("Avg cost per unit", text: $avgCostText)
                            .keyboardType(.decimalPad)
                            .font(.system(.body, design: .monospaced))
                            .focused($numericFocused)
                    }

                    if let basis = costBasis {
                        LabeledContent("Cost Basis", value: basis.asCurrency(code: account.wrappedCurrency))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Position")
                } footer: {
                    Text("Average cost is your average purchase price per unit.")
                }

                // MARK: Account context
                Section {
                    LabeledContent("Account", value: account.wrappedName)
                }
            }
            .navigationTitle(isEditing ? "Edit Asset" : "New Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveAsset)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { numericFocused = false }
                }
            }
        }
        .onAppear {
            preloadFields()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                symbolFocused = true
            }
        }
    }

    // MARK: - Helpers

    private func preloadFields() {
        guard let a = asset else { return }
        symbol      = a.wrappedSymbol
        assetName   = a.wrappedName
        assetType   = a.assetKind
        quantityText = String(format: "%g", a.quantity)
        avgCostText  = String(format: "%g", a.avgCost)
    }

    private func saveAsset() {
        guard let qty = parsedQuantity, let cost = parsedAvgCost else { return }
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespaces)
        let trimmedName   = assetName.trimmingCharacters(in: .whitespaces)

        if let existing = asset {
            existing.symbol    = trimmedSymbol
            existing.name      = trimmedName.isEmpty ? trimmedSymbol : trimmedName
            existing.assetType = assetType.rawValue
            existing.quantity  = qty
            existing.avgCost   = cost
        } else {
            let newAsset        = Asset(context: ctx)
            newAsset.id         = UUID()
            newAsset.symbol     = trimmedSymbol
            newAsset.name       = trimmedName.isEmpty ? trimmedSymbol : trimmedName
            newAsset.assetType  = assetType.rawValue
            newAsset.quantity   = qty
            newAsset.avgCost    = cost
            newAsset.account    = account
        }

        try? ctx.save()
        HapticService.success()
        dismiss()
    }
}

#Preview("Add") {
    let ctx = PersistenceController.preview.container.viewContext
    let account = try! ctx.fetch(Account.fetchRequest()).first!
    return AddEditAssetView(account: account)
        .environment(\.managedObjectContext, ctx)
}

#Preview("Edit") {
    let ctx = PersistenceController.preview.container.viewContext
    guard let asset = try? ctx.fetch(Asset.fetchRequest()).first,
          let account = asset.account else { return AnyView(Text("No preview data")) }
    return AnyView(
        AddEditAssetView(account: account, asset: asset)
            .environment(\.managedObjectContext, ctx)
    )
}
