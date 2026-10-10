import SwiftUI
import CoreData
import UserNotifications

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var ctx

    // Fetch all transactions for CSV export.
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.date)],
        animation: .none
    ) private var transactions: FetchedResults<CDTransaction>

    @AppStorage("currencyCode")          private var currencyCode          = "USD"
    @AppStorage("biometricEnabled")      private var biometricEnabled      = false
    @AppStorage("dailyReminderEnabled")  private var dailyReminderEnabled  = false
    @AppStorage("reminderTimeInterval")  private var reminderTimeInterval: Double = 9 * 3600
    @AppStorage("netWorthGoalEnabled")   private var goalEnabled           = false
    @AppStorage("netWorthGoalAmount")    private var goalAmount: Double     = 0
    @AppStorage("anthropicAPIKey")       private var anthropicAPIKey       = ""

    @State private var goalAmountText  = ""
    @State private var apiKeyText      = ""
    @State private var apiKeyVisible   = false
    @FocusState private var goalFocused: Bool

    // Binding shim: DatePicker needs a Date, @AppStorage stores a Double.
    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.startOfDay(for: .now)
                    .addingTimeInterval(reminderTimeInterval)
            },
            set: { newDate in
                let midnight = Calendar.current.startOfDay(for: .now)
                reminderTimeInterval = newDate.timeIntervalSince(midnight)
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Display
                Section("Display") {
                    Picker("Currency", selection: $currencyCode) {
                        ForEach([
                            "USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF",
                            "CNY", "INR", "MXN", "BRL", "KRW", "SGD", "HKD",
                            "NOK", "SEK", "DKK", "NZD", "ZAR", "AED", "THB"
                        ], id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                }

                // MARK: Budgets
                Section("Budgets") {
                    NavigationLink("Monthly Budgets") {
                        BudgetListView()
                            .environment(\.managedObjectContext, ctx)
                    }
                }

                // MARK: Goal
                Section {
                    Toggle(isOn: $goalEnabled) {
                        Label("Net Worth Goal", systemImage: "target")
                    }
                    .tint(Color.ledgerAccent)

                    if goalEnabled {
                        HStack {
                            Text(currencySymbol)
                                .foregroundStyle(.secondary)
                            TextField("Target amount", text: $goalAmountText)
                                .keyboardType(.decimalPad)
                                .focused($goalFocused)
                                .onChange(of: goalAmountText) { _, v in
                                    // Bug 6: always update so clearing the field resets the stored goal
                                    goalAmount = Double(v.replacingOccurrences(of: ",", with: "")) ?? 0
                                }
                        }
                    }
                } header: {
                    Text("Goal")
                } footer: {
                    if goalEnabled {
                        Text("Your progress toward this target is shown on the Dashboard.")
                    }
                }

                // MARK: Security
                Section("Security") {
                    Toggle(isOn: $biometricEnabled) {
                        Label("Face ID / Touch ID", systemImage: "faceid")
                    }
                    .tint(Color.ledgerAccent)
                }

                // MARK: Notifications
                Section {
                    Toggle(isOn: $dailyReminderEnabled) {
                        Label("Daily Reminder", systemImage: "bell")
                    }
                    .tint(Color.ledgerAccent)

                    if dailyReminderEnabled {
                        DatePicker(
                            "Reminder Time",
                            selection: reminderTimeBinding,
                            displayedComponents: [.hourAndMinute]
                        )
                    }

                    NavigationLink {
                        PriceAlertsView()
                            .environment(\.managedObjectContext, ctx)
                    } label: {
                        Label("Price Alerts", systemImage: "bell.badge")
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    if dailyReminderEnabled {
                        Text("You may be asked to allow notifications the first time you enable this.")
                    }
                }

                // MARK: Data
                Section("Data") {
                    if transactions.isEmpty {
                        LabeledContent("Export Transactions (CSV)") {
                            Text("No data yet")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ShareLink(
                            item: csvString,
                            subject: Text("Ledger Transactions"),
                            message: Text("Exported \(transactions.count) transactions from Ledger.")
                        ) {
                            Label("Export Transactions (CSV)", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                // MARK: Ask Claude
                Section {
                    HStack {
                        if apiKeyVisible {
                            TextField("sk-ant-…", text: $apiKeyText)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onSubmit { saveAPIKey() }
                        } else {
                            SecureField("sk-ant-…", text: $apiKeyText)
                                .onSubmit { saveAPIKey() }
                        }
                        Button {
                            apiKeyVisible.toggle()
                        } label: {
                            Image(systemName: apiKeyVisible ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        if !apiKeyText.isEmpty {
                            Button("Save") { saveAPIKey() }
                                .foregroundStyle(Color.ledgerAccent)
                                .fontWeight(.semibold)
                        }
                    }
                    if anthropicAPIKey.isEmpty {
                        Label("No key set — Ask Claude will not work.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Label("Key saved on this device only.", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.ledgerPositive)
                    }
                } header: {
                    Text("Ask Claude")
                } footer: {
                    Text("Your Anthropic API key is stored only on this device and never leaves it. Get a key at console.anthropic.com.")
                }

                // MARK: About
                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build",   value: buildNumber)
                    LabeledContent("Transactions", value: "\(transactions.count)")
                    // Replace this URL with your real privacy policy page before submitting.
                    if let url = URL(string: "https://example.com/ledger-privacy") {
                        Link(destination: url) {
                            Label("Privacy Policy", systemImage: "hand.raised")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { goalFocused = false }
                }
            }
        }
        .onAppear {
            if goalAmount > 0 {
                goalAmountText = String(format: "%.0f", goalAmount)
            }
            // Show masked placeholder if a key is already saved
            apiKeyText = anthropicAPIKey.isEmpty ? "" : String(repeating: "•", count: 16)
            syncCurrencyToAppGroup()
        }
        .onChange(of: currencyCode) { _, _ in syncCurrencyToAppGroup() }
        .onChange(of: dailyReminderEnabled) { _, enabled in
            if enabled {
                requestNotificationPermission()
            } else {
                UNUserNotificationCenter.current()
                    .removePendingNotificationRequests(withIdentifiers: ["ledger.daily"])
            }
        }
        .onChange(of: reminderTimeInterval) { _, _ in
            if dailyReminderEnabled { scheduleReminder() }
        }
    }

    // MARK: - Notification helpers

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, _ in
                DispatchQueue.main.async {
                    if granted { scheduleReminder() }
                    else { dailyReminderEnabled = false }
                }
            }
    }

    private func scheduleReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["ledger.daily"])

        let content = UNMutableNotificationContent()
        content.title = "Ledger"
        content.body  = "Don't forget to log today's trades and transactions."
        content.sound = .default

        let fireDate = Calendar.current.startOfDay(for: .now)
            .addingTimeInterval(reminderTimeInterval)
        let components = Calendar.current.dateComponents([.hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "ledger.daily",
                                            content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - API key save

    private func saveAPIKey() {
        let trimmed = apiKeyText.trimmingCharacters(in: .whitespaces)
        // Ignore if user submitted the masked placeholder
        guard !trimmed.isEmpty, !trimmed.allSatisfy({ $0 == "•" }) else { return }
        anthropicAPIKey = trimmed
        apiKeyText = String(repeating: "•", count: 16)
        HapticService.success()
    }

    // MARK: - Widget sync (Bug 2: @AppStorage uses standard suite; widget reads App Group)

    private func syncCurrencyToAppGroup() {
        UserDefaults(suiteName: "group.ledger")?.set(currencyCode, forKey: "currencyCode")
    }

    // MARK: - CSV generation

    private var csvString: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        var lines = ["Date,Account,Category,Type,Amount,Notes"]
        for tx in transactions {
            let date     = tx.date.map { formatter.string(from: $0) } ?? ""
            let account  = csvEscape(tx.account?.wrappedName ?? "")
            let category = csvEscape(tx.transactionCategory.displayName)
            let type     = tx.isExpense ? "Expense" : "Income"
            let amount   = String(format: "%.2f", tx.amount)
            let notes    = csvEscape(tx.wrappedNotes)
            lines.append("\(date),\(account),\(category),\(type),\(amount),\(notes)")
        }
        return lines.joined(separator: "\n")
    }

    // Wrap a field in quotes and escape internal quotes per RFC 4180.
    private func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: - Bundle helpers

    private var currencySymbol: String {
        let locale = Locale(identifier: Locale.identifier(fromComponents: [NSLocale.Key.currencyCode.rawValue: currencyCode]))
        return locale.currencySymbol ?? currencyCode
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}

#Preview {
    SettingsView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
}
