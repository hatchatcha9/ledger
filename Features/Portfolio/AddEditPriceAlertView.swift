import SwiftUI
import CoreData
import UserNotifications

struct AddEditPriceAlertView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    let symbol: String
    var alert: PriceAlert? = nil

    @State private var condition:   PriceAlertCondition = .above
    @State private var targetText   = ""
    @State private var note         = ""

    @FocusState private var priceFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Trigger") {
                    Picker("Condition", selection: $condition) {
                        ForEach(PriceAlertCondition.allCases) {
                            Label($0.displayName, systemImage: $0.icon).tag($0)
                        }
                    }
                    HStack {
                        Text("Target Price")
                        Spacer()
                        TextField("0.00", text: $targetText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($priceFocused)
                            .frame(width: 120)
                    }
                }

                Section("Label (optional)") {
                    TextField("e.g. Buy zone, Stop loss", text: $note)
                }

                Section {
                    HStack {
                        Image(systemName: condition.icon)
                            .foregroundStyle(Color.ledgerAccent)
                        Text("Alert me when **\(symbol)** \(condition.displayName.lowercased()) \(previewPrice)")
                            .font(.subheadline)
                    }
                } header: {
                    Text("Preview")
                }
            }
            .navigationTitle(alert == nil ? "New Price Alert" : "Edit Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(alert == nil ? "Save" : "Update") { save() }
                        .bold()
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { priceFocused = false }
                }
            }
            .onAppear { populate() }
        }
    }

    private var previewPrice: String {
        Double(targetText.replacingOccurrences(of: ",", with: ""))
            .map { $0.asCurrency() } ?? "—"
    }
    private var canSave: Bool {
        (Double(targetText.replacingOccurrences(of: ",", with: "")) ?? 0) > 0
    }

    private func populate() {
        guard let a = alert else { priceFocused = true; return }
        condition   = a.alertCondition
        targetText  = String(format: "%g", a.targetPrice)
        note        = a.wrappedNote
    }

    private func save() {
        guard let price = Double(targetText.replacingOccurrences(of: ",", with: "")), price > 0 else { return }
        let a         = alert ?? PriceAlert(context: ctx)
        if alert == nil { a.id = UUID(); a.createdAt = .now }
        a.symbol      = symbol
        a.targetPrice = price
        a.condition   = condition.rawValue
        a.note        = note.trimmingCharacters(in: .whitespaces)
        a.isActive    = true
        try? ctx.save()
        HapticService.success()
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _ in }
        dismiss()
    }
}

#Preview {
    AddEditPriceAlertView(symbol: "AAPL")
        .environment(\.managedObjectContext,
                     PersistenceController.preview.container.viewContext)
}
