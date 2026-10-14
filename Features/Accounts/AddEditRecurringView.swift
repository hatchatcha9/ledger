import SwiftUI

struct AddEditRecurringView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    let account: Account
    var recurring: RecurringTransaction? = nil

    @State private var name        = ""
    @State private var amountText  = ""
    @State private var isExpense   = true
    @State private var category: TransactionCategory  = .other
    @State private var frequency: RecurringFrequency  = .monthly
    @State private var nextDueDate = Date()
    @State private var notes       = ""
    @FocusState private var nameFocused: Bool
    @FocusState private var amountFocused: Bool

    private var isEditing: Bool { recurring != nil }

    private var parsedAmount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: ""))
    }

    private var canSave: Bool {
        guard let v = parsedAmount else { return false }
        return v > 0 && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Netflix, Rent, Paycheck", text: $name)
                        .focused($nameFocused)
                }

                Section {
                    Picker("", selection: $isExpense) {
                        Text("Expense").tag(true)
                        Text("Income").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .onChange(of: isExpense) { _ in autoselectCategory() }

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

                Section("Details") {
                    Picker("Category", selection: $category) {
                        ForEach(relevantCategories) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }

                    Picker("Repeats", selection: $frequency) {
                        ForEach(RecurringFrequency.allCases) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }

                    DatePicker("Next Due", selection: $nextDueDate, displayedComponents: [.date])

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(isEditing ? "Edit Recurring" : "New Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { amountFocused = false; nameFocused = false }
                }
            }
        }
        .onAppear {
            preload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { nameFocused = true }
        }
    }

    // MARK: - Helpers

    private var relevantCategories: [TransactionCategory] {
        isExpense
            ? TransactionCategory.allCases.filter { !$0.isIncome }
            : TransactionCategory.allCases.filter { $0.isIncome || $0 == .other }
    }

    private func autoselectCategory() {
        if isExpense {
            if category.isIncome { category = .other }
        } else {
            if !category.isIncome { category = .salary }
        }
    }

    private func preload() {
        guard let r = recurring else { return }
        name        = r.wrappedName
        amountText  = String(format: "%.2f", abs(r.amount))
        isExpense   = r.amount < 0
        category    = r.transactionCategory
        frequency   = r.recurringFrequency
        nextDueDate = r.nextDueDate ?? .now
        notes       = r.wrappedNotes
    }

    private func save() {
        guard let raw = parsedAmount else { return }
        let signed = isExpense ? -raw : raw

        if let existing = recurring {
            existing.name        = name.trimmingCharacters(in: .whitespaces)
            existing.amount      = signed
            existing.category    = category.rawValue
            existing.frequency   = frequency.rawValue
            existing.nextDueDate = nextDueDate
            existing.notes       = notes
        } else {
            let r          = RecurringTransaction(context: ctx)
            r.id           = UUID()
            r.name         = name.trimmingCharacters(in: .whitespaces)
            r.amount       = signed
            r.category     = category.rawValue
            r.frequency    = frequency.rawValue
            r.nextDueDate  = nextDueDate
            r.notes        = notes
            r.isActive     = true
            r.createdAt    = .now
            r.account      = account
        }

        try? ctx.save()
        HapticService.success()
        dismiss()
    }
}

#Preview {
    let ctx = PersistenceController.preview.container.viewContext
    let account = try! ctx.fetch(Account.fetchRequest()).first!
    return AddEditRecurringView(account: account)
        .environment(\.managedObjectContext, ctx)
}
