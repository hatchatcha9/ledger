import SwiftUI

// Used for both creating a new account (account == nil) and editing an existing one.
struct AddEditAccountView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    var account: Account? = nil   // nil → add mode
    var onSave:   () -> Void = {}
    var onDelete: () -> Void = {}   // called after deletion so parent can dismiss

    @State private var name = ""
    @State private var type: AccountType = .brokerage
    @State private var currency = "USD"
    @State private var initialBalanceText = ""
    @State private var showingDeleteAlert = false
    @FocusState private var balanceFocused: Bool

    private var isEditing: Bool { account != nil }

    // Save is only enabled when there's a non-blank name. In edit mode we don't
    // touch the balance — transactions drive that.
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Identity
                Section("Account Details") {
                    // The autofocus on .name is done via .focused() in iOS 17+.
                    TextField("Name, e.g. Fidelity Brokerage", text: $name)
                        .textInputAutocapitalization(.words)

                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases) { t in
                            Label(t.displayName, systemImage: t.icon).tag(t)
                        }
                    }
                }

                // MARK: Currency
                Section("Currency") {
                    Picker("Currency", selection: $currency) {
                        ForEach([
                            "USD","EUR","GBP","JPY","CAD","AUD","CHF",
                            "CNY","INR","MXN","BRL","KRW","SGD","HKD",
                            "NOK","SEK","DKK","NZD","ZAR","AED","THB"
                        ], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                }

                // MARK: Starting balance — add mode only
                if !isEditing {
                    Section {
                        HStack {
                            Text(currency)
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)
                            TextField("0.00", text: $initialBalanceText)
                                .keyboardType(.decimalPad)
                                .focused($balanceFocused)
                        }
                    } header: {
                        Text("Starting Balance")
                    } footer: {
                        Text("You can add transactions later to keep it accurate.")
                    }
                }

                // MARK: Danger zone — edit mode only
                if isEditing {
                    Section {
                        Button("Delete Account", role: .destructive) {
                            showingDeleteAlert = true
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Account" : "New Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveAccount)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { balanceFocused = false }
                }
            }
            .alert("Delete Account?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive, action: deleteAccount)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will also delete all transactions in this account. This cannot be undone.")
            }
        }
        .onAppear(perform: preloadFields)
    }

    // MARK: - Helpers

    private func preloadFields() {
        guard let account else { return }
        name     = account.wrappedName
        type     = account.accountType
        currency = account.wrappedCurrency
    }

    private func saveAccount() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        if let existing = account {
            existing.name     = trimmed
            existing.type     = type.rawValue
            existing.currency = currency
        } else {
            let newAccount       = Account(context: ctx)
            newAccount.id        = UUID()
            newAccount.name      = trimmed
            newAccount.type      = type.rawValue
            newAccount.currency  = currency
            newAccount.balance   = Double(initialBalanceText) ?? 0
            newAccount.createdAt = .now
        }

        try? ctx.save()
        HapticService.success()
        onSave()
        dismiss()
    }

    private func deleteAccount() {
        guard let account else { return }
        ctx.delete(account)
        try? ctx.save()
        HapticService.impact(.heavy)
        dismiss()
        onDelete()
    }
}

#Preview("Add") {
    AddEditAccountView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

#Preview("Edit") {
    let ctx = PersistenceController.preview.container.viewContext
    let account = try! ctx.fetch(Account.fetchRequest()).first!
    return AddEditAccountView(account: account)
        .environment(\.managedObjectContext, ctx)
}
