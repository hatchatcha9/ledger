import SwiftUI

struct AddEditBudgetView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    var budget: Budget? = nil
    var existingCategories: Set<String> = []

    @State private var category: TransactionCategory = .food
    @State private var limitText = ""
    @FocusState private var limitFocused: Bool

    private var isEditing: Bool { budget != nil }

    private var availableCategories: [TransactionCategory] {
        let taken = isEditing
            ? existingCategories.subtracting([budget?.category ?? ""])
            : existingCategories
        return TransactionCategory.expenseCategories.filter { !taken.contains($0.rawValue) }
    }

    private var parsedLimit: Double? {
        Double(limitText.replacingOccurrences(of: ",", with: ""))
    }

    private var canSave: Bool {
        guard let v = parsedLimit else { return false }
        return v > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(availableCategories) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                    .disabled(isEditing)
                }

                Section {
                    HStack {
                        Text("$")
                            .font(.title2.bold())
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $limitText)
                            .keyboardType(.decimalPad)
                            .font(.system(.title2, design: .monospaced).bold())
                            .focused($limitFocused)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Monthly Limit")
                }
            }
            .navigationTitle(isEditing ? "Edit Budget" : "New Budget")
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
                    Button("Done") { limitFocused = false }
                }
            }
        }
        .onAppear {
            if let b = budget {
                category  = b.transactionCategory
                limitText = String(format: "%.2f", b.monthlyLimit)
            } else if let first = availableCategories.first {
                category = first
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { limitFocused = true }
        }
    }

    private func save() {
        guard let limit = parsedLimit else { return }
        if let existing = budget {
            existing.monthlyLimit = limit
        } else {
            let b          = Budget(context: ctx)
            b.id           = UUID()
            b.category     = category.rawValue
            b.monthlyLimit = limit
            b.createdAt    = .now
        }
        try? ctx.save()
        HapticService.success()
        dismiss()
    }
}
