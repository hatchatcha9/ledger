import SwiftUI

struct DebtPayoffView: View {
    let account: Account

    @AppStorage("currencyCode") private var currencyCode = "USD"

    @State private var aprText      = ""
    @State private var extraText    = ""
    @FocusState private var focused: Bool

    // MARK: - Computed

    private var balance: Double { abs(account.balance) }

    private var apr: Double {
        Double(aprText.replacingOccurrences(of: "%", with: "")) ?? 0
    }
    private var extraPayment: Double {
        Double(extraText.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    // Minimum payment = 2% of balance or $25, whichever is larger (common card rule)
    private var minPayment: Double { max(balance * 0.02, 25) }

    private var monthlyRate: Double { apr / 100 / 12 }

    private struct PayoffResult {
        let months:        Int
        let totalInterest: Double
        let totalPaid:     Double
    }

    private func payoff(extra: Double) -> PayoffResult? {
        guard balance > 0 else { return nil }
        let payment = minPayment + extra
        guard payment > 0 else { return nil }

        if apr <= 0 {
            // No interest — simple division
            let months = Int(ceil(balance / payment))
            return PayoffResult(months: months, totalInterest: 0, totalPaid: payment * Double(months))
        }

        let r = monthlyRate
        guard r > 0, payment > balance * r else { return nil } // payment must exceed monthly interest

        // n = -log(1 - r*P/M) / log(1 + r)
        let n = -log(1 - r * balance / payment) / log(1 + r)
        let months = Int(ceil(n))
        let totalPaid = payment * Double(months)
        return PayoffResult(months: months, totalInterest: max(totalPaid - balance, 0), totalPaid: totalPaid)
    }

    private var baseResult:  PayoffResult? { payoff(extra: 0) }
    private var extraResult: PayoffResult? { extraPayment > 0 ? payoff(extra: extraPayment) : nil }

    private func monthLabel(_ months: Int) -> String {
        if months >= 12 {
            let y = months / 12, m = months % 12
            return m == 0 ? "\(y)y" : "\(y)y \(m)mo"
        }
        return "\(months) mo"
    }

    var body: some View {
        Form {
            // Current balance
            Section {
                VStack(spacing: 6) {
                    Text(balance.asCurrency(code: currencyCode))
                        .font(Theme.monoLargeTitle())
                        .foregroundStyle(.ledgerNegative)
                    Text("Outstanding Balance")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            // Inputs
            Section("Loan Details") {
                HStack {
                    Text("Annual Rate (APR)")
                        .foregroundStyle(.primary)
                    Spacer()
                    TextField("e.g. 24.99", text: $aprText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focused)
                        .frame(width: 100)
                    Text("%").foregroundStyle(.secondary)
                }

                HStack {
                    Text("Min. Monthly Payment")
                    Spacer()
                    Text(minPayment.asCurrency(code: currencyCode))
                        .font(Theme.monoBody())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Extra Monthly Payment")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(account.wrappedCurrency)
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $extraText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focused)
                        .frame(width: 100)
                }
            }

            // Minimum payment result
            if let base = baseResult {
                Section("Minimum Payments Only") {
                    resultRow(label: "Payoff Time",     value: monthLabel(base.months),
                              color: .ledgerNegative)
                    resultRow(label: "Total Interest",  value: base.totalInterest.asCurrency(code: currencyCode),
                              color: base.totalInterest > 0 ? .ledgerNegative : .secondary)
                    resultRow(label: "Total Paid",      value: base.totalPaid.asCurrency(code: currencyCode),
                              color: .primary)
                    if let target = Calendar.current.date(byAdding: .month, value: base.months, to: .now) {
                        resultRow(label: "Debt-Free Date",
                                  value: target.formatted(.dateTime.month(.abbreviated).year()),
                                  color: .secondary)
                    }
                }
            }

            // With extra payment result
            if let extra = extraResult, let base = baseResult {
                Section("With +\(extraPayment.asCurrency(code: currencyCode))/mo Extra") {
                    resultRow(label: "Payoff Time",    value: monthLabel(extra.months),
                              color: .ledgerPositive)
                    resultRow(label: "Months Saved",   value: "\(base.months - extra.months) months",
                              color: .ledgerPositive)
                    resultRow(label: "Interest Saved",
                              value: (base.totalInterest - extra.totalInterest).asCurrency(code: currencyCode),
                              color: .ledgerPositive)
                    resultRow(label: "Total Paid",     value: extra.totalPaid.asCurrency(code: currencyCode),
                              color: .primary)
                    if let target = Calendar.current.date(byAdding: .month, value: extra.months, to: .now) {
                        resultRow(label: "Debt-Free Date",
                                  value: target.formatted(.dateTime.month(.abbreviated).year()),
                                  color: .ledgerPositive)
                    }
                }
            }

            if apr > 0 && baseResult == nil {
                Section {
                    Label("Monthly interest exceeds the minimum payment. Increase your payment to make progress.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Debt Payoff")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    private func resultRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(Theme.monoBody().bold())
                .foregroundStyle(color)
        }
    }
}

#Preview {
    let ctx = PersistenceController.preview.container.viewContext
    let loan = Account(context: ctx)
    loan.id = UUID(); loan.name = "Student Loan"; loan.type = "loan"
    loan.balance = -18_400; loan.currency = "USD"
    return NavigationStack { DebtPayoffView(account: loan) }
        .environment(\.managedObjectContext, ctx)
}
