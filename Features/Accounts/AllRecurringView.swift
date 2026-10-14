import SwiftUI

struct AllRecurringView: View {
    @Environment(\.managedObjectContext) private var ctx
    @AppStorage("currencyCode") private var currencyCode = "USD"

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.amount)],
        predicate: NSPredicate(format: "isActive == YES"),
        animation: .default
    ) private var rules: FetchedResults<RecurringTransaction>

    @State private var editingRule: RecurringTransaction? = nil

    private var totalMonthlyExpenses: Double {
        rules
            .filter { $0.amount < 0 }
            .reduce(0) { $0 + monthlyEquivalent(of: $1) }
    }

    private var totalMonthlyIncome: Double {
        rules
            .filter { $0.amount > 0 }
            .reduce(0) { $0 + monthlyEquivalent(of: $1) }
    }

    var body: some View {
        List {
            if !rules.isEmpty {
                // MARK: Summary
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Monthly committed expenses")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(totalMonthlyExpenses.asCurrency(code: currencyCode))
                                .font(Theme.monoSubhead())
                                .foregroundStyle(.ledgerNegative)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Monthly income")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(totalMonthlyIncome.asCurrency(code: currencyCode))
                                .font(Theme.monoSubhead())
                                .foregroundStyle(.ledgerPositive)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // MARK: Expenses
            let expenses = rules.filter { $0.amount < 0 }
            if !expenses.isEmpty {
                Section("Expenses") {
                    ForEach(expenses) { rule in
                        Button { editingRule = rule } label: {
                            ruleRow(rule)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in deleteRules(expenses, offsets: offsets) }
                }
            }

            // MARK: Income
            let income = rules.filter { $0.amount > 0 }
            if !income.isEmpty {
                Section("Income") {
                    ForEach(income) { rule in
                        Button { editingRule = rule } label: {
                            ruleRow(rule)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in deleteRules(income, offsets: offsets) }
                }
            }

            if rules.isEmpty {
                if #available(iOS 17, *) {
                    ContentUnavailableView(
                        "No Recurring Rules",
                        systemImage: "repeat.circle",
                        description: Text("Add recurring transactions from individual account screens.")
                    )
                }
            }
        }
        .navigationTitle("Recurring Transactions")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $editingRule) { rule in
            if let account = rule.account {
                AddEditRecurringView(account: account, recurring: rule)
                    .environment(\.managedObjectContext, ctx)
            }
        }
    }

    // MARK: - Row

    private func ruleRow(_ rule: RecurringTransaction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: rule.transactionCategory.icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.ledgerAccent)
                .frame(width: 36, height: 36)
                .background(Color.ledgerAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.wrappedName)
                    .font(.subheadline)
                HStack(spacing: 4) {
                    Text(rule.recurringFrequency.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(rule.account?.wrappedName ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(abs(rule.amount).asCurrency(code: currencyCode))
                    .font(Theme.monoCaption())
                    .foregroundStyle(rule.amount < 0 ? Color.ledgerNegative : Color.ledgerPositive)
                Text("~\(monthlyEquivalent(of: rule).asCurrency(code: currencyCode))/mo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func monthlyEquivalent(of rule: RecurringTransaction) -> Double {
        let amt = abs(rule.amount)
        switch rule.recurringFrequency {
        case .weekly:   return amt * 4.33
        case .biweekly: return amt * 2.17
        case .monthly:  return amt
        case .yearly:   return amt / 12
        }
    }

    private func deleteRules(_ subset: [RecurringTransaction], offsets: IndexSet) {
        for i in offsets {
            subset[i].isActive = false
        }
        try? ctx.save()
    }
}

#Preview {
    NavigationStack {
        AllRecurringView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
