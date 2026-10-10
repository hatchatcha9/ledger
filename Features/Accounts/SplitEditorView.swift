import SwiftUI

struct SplitEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let total: Double
    let currencyCode: String
    @Binding var splits: [TransactionSplit]

    @State private var localSplits: [TransactionSplit] = []

    private var allocated: Double { localSplits.reduce(0) { $0 + $1.amount } }
    private var remaining: Double { total - allocated }
    private var isBalanced: Bool  { abs(remaining) < 0.01 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Total")
                        Spacer()
                        Text(total.asCurrency(code: currencyCode))
                            .font(Theme.monoBody())
                    }
                    HStack {
                        Text("Allocated")
                        Spacer()
                        Text(allocated.asCurrency(code: currencyCode))
                            .font(Theme.monoBody())
                            .foregroundStyle(isBalanced ? .ledgerPositive : .orange)
                    }
                    if !isBalanced {
                        HStack {
                            Text("Remaining")
                            Spacer()
                            Text(remaining.asCurrency(code: currencyCode))
                                .font(Theme.monoBody().bold())
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section("Splits") {
                    ForEach($localSplits) { $split in
                        SplitRowEditor(split: $split, currencyCode: currencyCode)
                    }
                    .onDelete { offsets in localSplits.remove(atOffsets: offsets) }

                    Button {
                        let leftover = max(remaining, 0)
                        localSplits.append(
                            TransactionSplit(amount: leftover, category: TransactionCategory.other.rawValue)
                        )
                    } label: {
                        Label("Add Split", systemImage: "plus.circle")
                            .foregroundStyle(Color.ledgerAccent)
                    }
                }

                if !isBalanced && !localSplits.isEmpty {
                    Section {
                        Label("Splits must total \(total.asCurrency(code: currencyCode)). Adjust amounts above.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Split Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        splits = localSplits
                        dismiss()
                    }
                    .bold()
                    .disabled(!isBalanced || localSplits.isEmpty)
                }
            }
            .onAppear {
                localSplits = splits.isEmpty
                    ? [TransactionSplit(amount: total, category: TransactionCategory.other.rawValue)]
                    : splits
            }
        }
    }
}

// MARK: - Split Row Editor

private struct SplitRowEditor: View {
    @Binding var split: TransactionSplit
    let currencyCode: String

    @State private var amountText = ""
    @FocusState private var focused: Bool

    private var category: TransactionCategory {
        get { TransactionCategory(rawValue: split.category) ?? .other }
    }

    var body: some View {
        VStack(spacing: 6) {
            Picker("Category", selection: Binding(
                get: { category },
                set: { split.category = $0.rawValue }
            )) {
                ForEach(TransactionCategory.allCases) { cat in
                    Label(cat.displayName, systemImage: cat.icon).tag(cat)
                }
            }

            HStack {
                Text("Amount")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .focused($focused)
                    .onChange(of: amountText) { _, v in
                        if let d = Double(v.replacingOccurrences(of: ",", with: "")) {
                            split.amount = d
                        }
                    }
            }
        }
        .onAppear {
            amountText = split.amount > 0 ? String(format: "%.2f", split.amount) : ""
        }
    }
}
