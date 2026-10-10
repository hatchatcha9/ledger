import SwiftUI
import CoreData

// Creates a matching debit + credit across two accounts.
struct AccountTransferView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.createdAt)],
        animation: .none
    ) private var accounts: FetchedResults<Account>

    @State private var fromAccount: Account?
    @State private var toAccount:   Account?
    @State private var amountText   = ""
    @State private var note         = ""
    @State private var date         = Date()

    @FocusState private var amountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Transfer") {
                    accountPicker(label: "From", selection: $fromAccount,
                                  exclude: toAccount)
                    accountPicker(label: "To",   selection: $toAccount,
                                  exclude: fromAccount)
                }

                Section("Amount") {
                    HStack {
                        Text(fromAccount?.wrappedCurrency ?? "USD")
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                    }
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                }

                Section("Note (optional)") {
                    TextField("e.g. Move to savings", text: $note)
                }
            }
            .navigationTitle("Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Transfer") { save() }
                        .bold()
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { amountFocused = false }
                }
            }
        }
    }

    private var canSave: Bool {
        fromAccount != nil && toAccount != nil && fromAccount?.objectID != toAccount?.objectID
            && (Double(amountText) ?? 0) > 0
    }

    @ViewBuilder
    private func accountPicker(label: String, selection: Binding<Account?>,
                                exclude: Account?) -> some View {
        Picker(label, selection: selection) {
            Text("Select account").tag(Optional<Account>.none)
            ForEach(accounts.filter { $0.objectID != exclude?.objectID }) { acct in
                Text(acct.wrappedName).tag(Optional(acct))
            }
        }
    }

    private func save() {
        guard let from = fromAccount, let to = toAccount,
              let amount = Double(amountText.replacingOccurrences(of: ",", with: "")),
              amount > 0 else { return }

        let memo = note.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Transfer to \(to.wrappedName)"
            : note

        // Debit — negative in source account
        let debit        = CDTransaction(context: ctx)
        debit.id         = UUID()
        debit.amount     = -amount
        debit.category   = TransactionCategory.other.rawValue
        debit.type       = "expense"
        debit.date       = date
        debit.notes      = memo
        debit.createdAt  = .now
        debit.account    = from
        from.balance    -= amount

        // Credit — positive in destination account
        let credit       = CDTransaction(context: ctx)
        credit.id        = UUID()
        credit.amount    = amount
        credit.category  = TransactionCategory.other.rawValue
        credit.type      = "income"
        credit.date      = date
        credit.notes     = "Transfer from \(from.wrappedName)"
        credit.createdAt = .now
        credit.account   = to
        to.balance      += amount

        try? ctx.save()
        HapticService.success()
        dismiss()
    }
}

#Preview {
    AccountTransferView()
        .environment(\.managedObjectContext,
                     PersistenceController.preview.container.viewContext)
}
