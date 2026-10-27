import SwiftUI

struct AddEditJournalEntryView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    var entry: JournalEntry? = nil   // nil → add mode

    init(entry: JournalEntry? = nil,
         prefillSymbol: String = "",
         prefillDirection: TradeDirection = .long,
         prefillStrategyTag: String = "",
         prefillNotes: String = "") {
        self.entry = entry
        _symbol       = State(initialValue: prefillSymbol)
        _direction    = State(initialValue: prefillDirection)
        _strategyTag  = State(initialValue: prefillStrategyTag)
        _notes        = State(initialValue: prefillNotes)
    }

    // Form state
    @State private var symbol       = ""
    @State private var direction: TradeDirection = .long
    @State private var entryPriceText = ""
    @State private var entryDate    = Date()
    @State private var conviction: Int = 3
    @State private var strategyTag  = ""
    @State private var outcome: TradeOutcome = .open
    @State private var exitPriceText  = ""
    @State private var exitDate     = Date()
    @State private var notes        = ""
    @State private var showDeleteAlert = false
    @FocusState private var symbolFocused: Bool

    private var isEditing: Bool { entry != nil }

    private var parsedEntryPrice: Double? {
        Double(entryPriceText.replacingOccurrences(of: ",", with: ""))
    }

    private var parsedExitPrice: Double? {
        Double(exitPriceText.replacingOccurrences(of: ",", with: ""))
    }

    // Exit price required when the trade is closed.
    private var canSave: Bool {
        let sym = symbol.trimmingCharacters(in: .whitespaces)
        guard !sym.isEmpty, (parsedEntryPrice ?? 0) > 0 else { return false }
        if outcome != .open { return (parsedExitPrice ?? 0) > 0 }
        return true
    }

    // Realised P&L preview — shown when we have both prices.
    private var realisedPnL: Double? {
        guard outcome != .open,
              let ep = parsedEntryPrice, ep > 0,
              let xp = parsedExitPrice,  xp > 0 else { return nil }
        let multiplier: Double = direction == .long ? 1 : -1
        return multiplier * (xp - ep)
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Trade identity
                Section("Trade") {
                    Picker("Direction", selection: $direction) {
                        ForEach(TradeDirection.allCases) { d in
                            Text(d.displayName).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    TextField("Symbol, e.g. BTC", text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($symbolFocused)
                        .onChange(of: symbol) { new in symbol = new.uppercased() }
                }

                // MARK: Entry
                Section("Entry") {
                    HStack {
                        Text("USD")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)
                        TextField("Entry price", text: $entryPriceText)
                            .keyboardType(.decimalPad)
                            .font(.system(.body, design: .monospaced))
                    }

                    DatePicker(
                        "Entry Date",
                        selection: $entryDate,
                        in: ...Date(),
                        displayedComponents: [.date]
                    )
                }

                // MARK: Outcome
                Section("Outcome") {
                    Picker("Outcome", selection: $outcome) {
                        ForEach(TradeOutcome.allCases) { o in
                            Label(o.displayName, systemImage: o.icon).tag(o)
                        }
                    }
                    .onChange(of: outcome) { new in
                        // Pre-fill exit date to entry date when closing the trade.
                        if new != .open && exitDate < entryDate { exitDate = entryDate }
                    }

                    if outcome != .open {
                        HStack {
                            Text("USD")
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .leading)
                            TextField("Exit price", text: $exitPriceText)
                                .keyboardType(.decimalPad)
                                .font(.system(.body, design: .monospaced))
                        }

                        DatePicker(
                            "Exit Date",
                            selection: $exitDate,
                            in: entryDate...Date(),
                            displayedComponents: [.date]
                        )

                        if let pnl = realisedPnL {
                            LabeledContent("Realised P&L") {
                                Text(pnl.asCurrency())
                                    .font(Theme.monoBody())
                                    .foregroundStyle(pnl >= 0 ? .ledgerPositive : .ledgerNegative)
                            }
                        }
                    }
                }

                // MARK: Details
                Section("Details") {
                    convictionRow

                    TextField("Strategy tag (optional)", text: $strategyTag)
                        .autocorrectionDisabled()

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                // MARK: Danger zone — edit mode only
                if isEditing {
                    Section {
                        Button("Delete Entry", role: .destructive) {
                            showDeleteAlert = true
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Entry" : "New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveEntry)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .alert("Delete Entry?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let e = entry { ctx.delete(e); try? ctx.save() }
                    HapticService.impact(.heavy)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        }
        .onAppear {
            preloadFields()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                symbolFocused = true
            }
        }
    }

    // MARK: - Conviction row (interactive star rating)

    private var convictionRow: some View {
        HStack {
            Text("Conviction")
            Spacer()
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: conviction >= star ? "star.fill" : "star")
                        .foregroundStyle(conviction >= star ? Color.yellow : Color.secondary)
                        .font(.title3)
                        .onTapGesture {
                            // Tapping the current rating again clears it to 0.
                            conviction = conviction == star ? 0 : star
                        }
                }
            }
        }
    }

    // MARK: - Persistence

    private func preloadFields() {
        guard let e = entry else { return }
        symbol         = e.wrappedSymbol
        direction      = e.tradeDirection
        entryPriceText = String(format: "%g", e.entryPrice)
        entryDate      = e.entryDate ?? .now
        conviction     = Int(e.conviction)
        strategyTag    = e.wrappedStrategyTag
        outcome        = e.tradeOutcome
        if e.exitPrice != 0 { exitPriceText = String(format: "%g", e.exitPrice) }
        exitDate       = e.exitDate ?? e.entryDate ?? .now
        notes          = e.wrappedNotes
    }

    private func saveEntry() {
        guard let ep = parsedEntryPrice else { return }
        let trimmedSym = symbol.trimmingCharacters(in: .whitespaces)
        let xp = parsedExitPrice ?? 0

        if let existing = entry {
            existing.symbol      = trimmedSym
            existing.direction   = direction.rawValue
            existing.entryPrice  = ep
            existing.entryDate   = entryDate
            existing.conviction  = Int16(conviction)
            existing.strategyTag = strategyTag.isEmpty ? nil : strategyTag
            existing.outcome     = outcome.rawValue
            existing.exitPrice   = outcome != .open ? xp : 0
            existing.exitDate    = outcome != .open ? exitDate : nil
            existing.notes       = notes.isEmpty ? nil : notes
        } else {
            let e          = JournalEntry(context: ctx)
            e.id           = UUID()
            e.symbol       = trimmedSym
            e.direction    = direction.rawValue
            e.entryPrice   = ep
            e.entryDate    = entryDate
            e.conviction   = Int16(conviction)
            e.strategyTag  = strategyTag.isEmpty ? nil : strategyTag
            e.outcome      = outcome.rawValue
            e.exitPrice    = outcome != .open ? xp : 0
            e.exitDate     = outcome != .open ? exitDate : nil
            e.notes        = notes.isEmpty ? nil : notes
            e.createdAt    = .now
        }

        try? ctx.save()
        HapticService.success()
        dismiss()
    }
}

#Preview("Add") {
    AddEditJournalEntryView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

#Preview("Edit") {
    let ctx = PersistenceController.preview.container.viewContext
    let entry = try! ctx.fetch(JournalEntry.fetchRequest()).first!
    return AddEditJournalEntryView(entry: entry)
        .environment(\.managedObjectContext, ctx)
}
