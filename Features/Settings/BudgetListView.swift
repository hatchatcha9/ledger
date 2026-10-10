import SwiftUI
import CoreData

struct BudgetListView: View {
    @Environment(\.managedObjectContext) private var ctx

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.category)],
        animation: .default
    ) private var budgets: FetchedResults<Budget>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.date)],
        animation: .default
    ) private var allTransactions: FetchedResults<CDTransaction>

    @State private var showingAdd  = false
    @State private var editing: Budget? = nil

    var body: some View {
        List {
            if budgets.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.largeTitle)
                        .foregroundStyle(.quaternary)
                    Text("No budgets yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Set monthly spending limits per category.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .listRowBackground(Color.clear)
            } else {
                ForEach(budgets) { budget in
                    BudgetRow(budget: budget, spent: spent(for: budget))
                        .contentShape(Rectangle())
                        .onTapGesture { editing = budget }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Budgets")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(budgets.count >= TransactionCategory.expenseCategories.count)
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddEditBudgetView(existingCategories: Set(budgets.compactMap(\.category)))
                .environment(\.managedObjectContext, ctx)
        }
        .sheet(item: $editing) { budget in
            AddEditBudgetView(budget: budget, existingCategories: Set(budgets.compactMap(\.category)))
                .environment(\.managedObjectContext, ctx)
        }
    }

    private func spent(for budget: Budget) -> Double {
        let calendar = Calendar.current
        let now = Date()
        let year  = calendar.component(.year,  from: now)
        let month = calendar.component(.month, from: now)
        return allTransactions
            .filter { tx in
                guard tx.amount < 0,
                      tx.category == budget.category,
                      let d = tx.date else { return false }
                return calendar.component(.year,  from: d) == year &&
                       calendar.component(.month, from: d) == month
            }
            .reduce(0) { $0 + abs($1.amount) }
    }

    private func delete(at offsets: IndexSet) {
        offsets.map { budgets[$0] }.forEach(ctx.delete)
        try? ctx.save()
    }
}

// MARK: - Budget Row

private struct BudgetRow: View {
    @ObservedObject var budget: Budget
    let spent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(budget.transactionCategory.displayName,
                      systemImage: budget.transactionCategory.icon)
                    .font(.body)
                Spacer()
                Text("\(spent.asCurrency()) / \(budget.monthlyLimit.asCurrency())")
                    .font(Theme.monoCaption())
                    .foregroundStyle(statusColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemFill))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(statusColor)
                        .frame(width: geo.size.width * min(ratio, 1.0), height: 6)
                }
            }
            .frame(height: 6)

            Text(footerText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var ratio: Double {
        guard budget.monthlyLimit > 0 else { return 0 }
        return spent / budget.monthlyLimit
    }

    private var statusColor: Color {
        switch ratio {
        case ..<0.75: return .ledgerPositive
        case 0.75..<1.0: return .orange
        default: return .ledgerNegative
        }
    }

    private var footerText: String {
        let remaining = budget.monthlyLimit - spent
        if remaining >= 0 {
            return "\(remaining.asCurrency()) left this month"
        } else {
            return "\(abs(remaining).asCurrency()) over budget"
        }
    }
}
