import SwiftUI

struct AddEditTransactionView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    let account: Account
    var transaction: CDTransaction? = nil   // nil → add mode
    var onSave: () -> Void = {}

    // Form state
    @State private var amountText = ""
    @State private var isExpense = true
    @State private var category: TransactionCategory = .other
    @State private var date = Date()
    @State private var notes = ""
    @State private var splits: [TransactionSplit] = []
    @State private var selectedTags: Set<String>  = []
    @State private var showingSplitEditor = false
    @State private var showingLargeAmountAlert = false
    @FocusState private var amountFocused: Bool

    private var isSplit: Bool { !splits.isEmpty }
    private var splitsTotal: Double { splits.reduce(0) { $0 + $1.amount } }
    private var splitsBalanced: Bool {
        guard let total = parsedAmount, isSplit else { return true }
        return abs(splitsTotal - total) < 0.01
    }

    private var isEditing: Bool { transaction != nil }

    private var parsedAmount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: ""))
    }

    private var canSave: Bool {
        guard let v = parsedAmount else { return false }
        return v > 0 && (splits.isEmpty || splitsBalanced)
    }

    // Average absolute amount for the selected category over the last 3 months.
    private var recentCategoryAverage: Double? {
        guard let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: .now)
        else { return nil }
        let matching = account.transactionsArray
            .filter {
                $0.transactionCategory == category &&
                ($0.date ?? .distantPast) >= threeMonthsAgo
            }
        guard matching.count >= 3 else { return nil }
        return matching.reduce(0) { $0 + abs($1.amount) } / Double(matching.count)
    }

    private var isLargeAmount: Bool {
        guard let entered = parsedAmount, let avg = recentCategoryAverage else { return false }
        return entered >= avg * 10
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Amount + direction
                Section {
                    // Segmented: Expense / Income
                    Picker("", selection: $isExpense) {
                        Text("Expense").tag(true)
                        Text("Income").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .onChange(of: isExpense) { _ in autoselectCategory() }

                    // Amount field — large, prominent
                    HStack {
                        Text(account.wrappedCurrency)
                            .font(.title2.bold())
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(.title2, design: .monospaced).bold())
                            .focused($amountFocused)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Amount")
                }

                // MARK: Details
                Section("Details") {
                    Picker("Category", selection: $category) {
                        ForEach(relevantCategories) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }

                    DatePicker(
                        "Date",
                        selection: $date,
                        displayedComponents: [.date]
                    )

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                // MARK: Splits
                Section {
                    if splits.isEmpty {
                        Button {
                            guard let total = parsedAmount, total > 0 else { return }
                            showingSplitEditor = true
                        } label: {
                            Label("Split Transaction", systemImage: "scissors")
                                .foregroundStyle(Color.ledgerAccent)
                        }
                        .disabled(parsedAmount == nil)
                    } else {
                        ForEach(splits) { split in
                            HStack {
                                Image(systemName: split.transactionCategory.icon)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(split.category)
                                    .font(.subheadline)
                                Spacer()
                                Text(split.amount.asCurrency(code: account.wrappedCurrency))
                                    .font(Theme.monoBody())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !splitsBalanced, let total = parsedAmount {
                            Label("Splits total \(splitsTotal.asCurrency(code: account.wrappedCurrency)) — needs \(total.asCurrency(code: account.wrappedCurrency))", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Button("Edit Splits") {
                            showingSplitEditor = true
                        }
                        .foregroundStyle(Color.ledgerAccent)
                        Button("Remove Splits", role: .destructive) {
                            splits = []
                        }
                    }
                } header: {
                    if isSplit { Text("Splits") }
                }

                // MARK: Tags
                Section("Tags") {
                    FlowTagPicker(
                        allTags:      CDTransaction.predefinedTags,
                        selectedTags: $selectedTags
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }

                // MARK: Account info (read-only, helpful context)
                Section {
                    LabeledContent("Account", value: account.wrappedName)
                    LabeledContent("Current Balance", value: account.balance.asCurrency(code: account.wrappedCurrency))
                }
            }
            .navigationTitle(isEditing ? "Edit Transaction" : "New Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if isLargeAmount && !isEditing {
                            showingLargeAmountAlert = true
                        } else {
                            saveTransaction()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { amountFocused = false }
                }
            }
        }
        .sheet(isPresented: $showingSplitEditor) {
            SplitEditorView(
                total: parsedAmount ?? 0,
                currencyCode: account.wrappedCurrency,
                splits: $splits
            )
        }
        .alert("Unusually Large Amount", isPresented: $showingLargeAmountAlert) {
            Button("Save Anyway", role: .destructive) { saveTransaction() }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let entered = parsedAmount, let avg = recentCategoryAverage {
                Text("\(entered.asCurrency(code: account.wrappedCurrency)) is more than 10× your recent average of \(avg.asCurrency(code: account.wrappedCurrency)) for \(category.displayName). Double-check before saving.")
            }
        }
        .onAppear {
            preloadFields()
            // Auto-focus the amount field so the keyboard appears immediately.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                amountFocused = true
            }
        }
    }

    // MARK: - Helpers

    // Show income-appropriate categories when the toggle flips to Income.
    private var relevantCategories: [TransactionCategory] {
        if isExpense {
            return TransactionCategory.allCases.filter { !$0.isIncome }
        } else {
            return TransactionCategory.allCases.filter { $0.isIncome || $0 == .other }
        }
    }

    private func autoselectCategory() {
        // Jump to a sensible default when the user flips the direction toggle.
        if isExpense {
            if category.isIncome { category = .other }
        } else {
            if !category.isIncome { category = .salary }
        }
    }

    private func preloadFields() {
        guard let tx = transaction else { return }
        let raw = tx.amount
        amountText   = String(format: "%.2f", abs(raw))
        isExpense    = raw < 0
        category     = tx.transactionCategory
        date         = tx.date ?? .now
        notes        = tx.wrappedNotes
        splits       = tx.splits
        selectedTags = Set(tx.wrappedTags)
    }

    private func saveTransaction() {
        guard let raw = parsedAmount else { return }
        // Expenses are negative amounts in the store.
        let signed = isExpense ? -raw : raw

        if let existing = transaction {
            // Reverse the old effect on the balance, apply the new one.
            account.balance -= existing.amount
            account.balance += signed

            existing.amount   = signed
            existing.category = category.rawValue
            existing.type     = isExpense ? "expense" : "income"
            existing.date     = date
            existing.notes    = notes
            existing.splits   = splits
            existing.setTags(Array(selectedTags))
        } else {
            let tx       = CDTransaction(context: ctx)
            tx.id        = UUID()
            tx.amount    = signed
            tx.category  = category.rawValue
            tx.type      = isExpense ? "expense" : "income"
            tx.date      = date
            tx.notes     = notes
            tx.createdAt = .now
            tx.account   = account
            tx.splits    = splits
            tx.setTags(Array(selectedTags))

            // Mirror the transaction on the account balance.
            account.balance += signed
        }

        try? ctx.save()
        HapticService.success()
        onSave()
        dismiss()
    }
}

#Preview {
    let ctx = PersistenceController.preview.container.viewContext
    let account = try! ctx.fetch(Account.fetchRequest()).first!
    return AddEditTransactionView(account: account)
        .environment(\.managedObjectContext, ctx)
}
