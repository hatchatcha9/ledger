import SwiftUI
import CoreData

struct AccountsView: View {
    @Environment(\.managedObjectContext) private var ctx

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.createdAt)],
        animation: .default
    ) private var accounts: FetchedResults<Account>

    @State private var showingAddAccount  = false
    @State private var showingTransfer    = false

    // Net worth = sum of all account balances.
    private var netWorth: Double {
        accounts.reduce(0) { $0 + $1.balance }
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Net worth summary
                if !accounts.isEmpty {
                    Section {
                        VStack(spacing: 4) {
                            Text(netWorth.asCurrency())
                                .font(Theme.monoLargeTitle())
                                .contentTransition(.numericText())
                                .animation(.spring(.smooth), value: netWorth)
                            Text("Total Net Worth")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }

                // MARK: Account list
                Section("Accounts") {
                    ForEach(accounts) { account in
                        NavigationLink {
                            AccountDetailView(account: account)
                        } label: {
                            AccountRow(account: account)
                        }
                    }
                    .onDelete(perform: deleteAccounts)
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingAddAccount = true
                        } label: {
                            Label("New Account", systemImage: "plus")
                        }
                        if accounts.count >= 2 {
                            Button {
                                showingTransfer = true
                            } label: {
                                Label("Transfer Between Accounts", systemImage: "arrow.left.arrow.right")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showingAddAccount) {
                AddEditAccountView()
                    .environment(\.managedObjectContext, ctx)
            }
            .sheet(isPresented: $showingTransfer) {
                AccountTransferView()
                    .environment(\.managedObjectContext, ctx)
            }
            .overlay {
                if accounts.isEmpty {
                    ContentUnavailableView {
                        Label("No Accounts", systemImage: "creditcard")
                    } description: {
                        Text("Add an account to start tracking your money.")
                    } actions: {
                        Button("Add Account") { showingAddAccount = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func deleteAccounts(at offsets: IndexSet) {
        HapticService.impact(.rigid)
        offsets.map { accounts[$0] }.forEach(ctx.delete)
        try? ctx.save()
    }
}

// MARK: - Account Row
private struct AccountRow: View {
    @ObservedObject var account: Account

    // 30-day change: current balance minus sum of transactions in last 30 days.
    private var change30d: Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        let recent = account.transactionsArray.filter { ($0.date ?? .distantPast) >= cutoff }
        guard !recent.isEmpty else { return nil }
        let priorBalance = account.balance - recent.reduce(0) { $0 + $1.amount }
        guard abs(priorBalance) > 0.01 else { return nil }
        return ((account.balance - priorBalance) / abs(priorBalance)) * 100
    }

    var body: some View {
        HStack(spacing: Theme.s12) {
            Image(systemName: account.accountType.icon)
                .font(.body)
                .foregroundStyle(Color.ledgerAccent)
                .frame(width: 38, height: 38)
                .background(Color.ledgerAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusS))

            VStack(alignment: .leading, spacing: 2) {
                Text(account.wrappedName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(account.accountType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(account.balance.asCurrency(code: account.wrappedCurrency))
                    .font(Theme.monoBody())
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.spring(.smooth), value: account.balance)

                if let pct = change30d {
                    HStack(spacing: 2) {
                        Image(systemName: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text(pct.asChangePercent())
                            .font(.caption)
                    }
                    .foregroundStyle(Color.changeColor(for: pct))
                } else {
                    Text("\(account.transactionsArray.count) tx")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, Theme.s4)
    }
}

#Preview {
    AccountsView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
}
