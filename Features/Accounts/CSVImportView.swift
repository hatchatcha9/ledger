import SwiftUI
import UniformTypeIdentifiers
import CoreData

struct CSVImportView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss)             private var dismiss

    let account: Account

    // MARK: - State

    private enum ImportState {
        case idle
        case parsed(CSVImportResult)
        case error(String)
        case done(Int)
    }

    @State private var importState:      ImportState = .idle
    @State private var showingPicker     = false
    @State private var isImporting       = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                switch importState {
                case .idle:
                    idleView
                case .parsed(let result):
                    previewView(result: result)
                case .error(let msg):
                    errorView(message: msg)
                case .done(let count):
                    doneView(count: count)
                }
            }
            .navigationTitle("Import CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.commaSeparatedText, .text, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFilePick(result)
        }
    }

    // MARK: - Idle view

    private var idleView: some View {
        VStack(spacing: Theme.s24) {
            Spacer()

            VStack(spacing: Theme.s16) {
                ZStack {
                    Circle()
                        .fill(Color.ledgerAccent.opacity(0.1))
                        .frame(width: 80, height: 80)
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.ledgerAccent)
                }

                VStack(spacing: Theme.s8) {
                    Text("Import from Bank")
                        .font(.title2.bold())
                    Text("Export a CSV statement from your bank's website, then select it here. Works with Chase, Bank of America, Wells Fargo, Citi, and most standard exports.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.s16)
                }
            }

            VStack(spacing: Theme.s12) {
                Button {
                    showingPicker = true
                } label: {
                    Label("Select CSV File", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.ledgerAccent)
                .controlSize(.large)

                VStack(alignment: .leading, spacing: Theme.s8) {
                    tipRow(icon: "minus.circle",   text: "Expenses should be negative amounts")
                    tipRow(icon: "clock",          text: "Duplicate transactions are skipped automatically")
                    tipRow(icon: "building.columns", text: "Importing into: \(account.wrappedName)")
                }
                .padding(Theme.s16)
                .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
            }
            .padding(.horizontal, Theme.s16)

            Spacer()
        }
    }

    // MARK: - Preview view

    private func previewView(result: CSVImportResult) -> some View {
        List {
            // Summary card
            Section {
                VStack(spacing: Theme.s12) {
                    HStack(spacing: Theme.s24) {
                        statPill(value: "\(result.rows.count)",         label: "Found")
                        statPill(value: "\(result.newRows.count)",      label: "New",       color: .ledgerPositive)
                        statPill(value: "\(result.duplicateCount)",     label: "Duplicates", color: .secondary)
                        statPill(value: "\(result.unparsedCount)",      label: "Skipped",   color: result.unparsedCount > 0 ? .orange : .secondary)
                    }
                    .frame(maxWidth: .infinity)

                    if result.newRows.isEmpty {
                        Label("All transactions already exist in this account.",
                              systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.ledgerPositive)
                    }
                }
                .padding(.vertical, Theme.s8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            // Preview rows (first 8)
            if !result.rows.isEmpty {
                Section("Preview (first \(min(result.rows.count, 8)))") {
                    ForEach(result.rows.prefix(8)) { row in
                        PreviewRow(row: row)
                    }
                    if result.rows.count > 8 {
                        Text("+ \(result.rows.count - 8) more transactions…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, Theme.s4)
                    }
                }
            }

            // Import button
            if !result.newRows.isEmpty {
                Section {
                    Button {
                        importRows(result.newRows)
                    } label: {
                        if isImporting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Import \(result.newRows.count) Transaction\(result.newRows.count == 1 ? "" : "s")",
                                  systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                    }
                    .listRowBackground(Color.ledgerAccent)
                    .foregroundStyle(.white)
                    .disabled(isImporting)
                }
            }

            // Try different file
            Section {
                Button {
                    importState = .idle
                } label: {
                    Label("Choose Different File", systemImage: "folder")
                        .foregroundStyle(Color.ledgerAccent)
                }
            }
        }
    }

    // MARK: - Error view

    private func errorView(message: String) -> some View {
        VStack(spacing: Theme.s24) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            VStack(spacing: Theme.s8) {
                Text("Couldn't Read File")
                    .font(.title3.bold())
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.s24)
            }
            Button("Try Another File") {
                importState = .idle
                showingPicker = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ledgerAccent)
            Spacer()
        }
    }

    // MARK: - Done view

    private func doneView(count: Int) -> some View {
        VStack(spacing: Theme.s24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.ledgerPositive)
            VStack(spacing: Theme.s8) {
                Text("Import Complete")
                    .font(.title2.bold())
                Text("\(count) transaction\(count == 1 ? "" : "s") added to \(account.wrappedName).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Color.ledgerAccent)
                .controlSize(.large)
            Spacer()
        }
    }

    // MARK: - Actions

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure:
            importState = .error("Couldn't open the file. Make sure it's a CSV exported from your bank.")
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importState = .error("Permission denied. Try exporting the file again.")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let text = (try? String(contentsOf: url, encoding: .utf8))
                          ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else {
                importState = .error("Couldn't read the file. Make sure it's a plain CSV text file.")
                return
            }

            let parsed = CSVImportService.parse(text, existingTransactions: account.transactionsArray)

            if parsed.rows.isEmpty {
                importState = .error("No transactions found. Make sure this is a CSV statement exported from your bank.")
            } else {
                HapticService.impact(.soft)
                importState = .parsed(parsed)
            }
        }
    }

    private func importRows(_ rows: [ParsedRow]) {
        isImporting = true
        HapticService.impact(.medium)

        for row in rows {
            let tx       = CDTransaction(context: ctx)
            tx.id        = UUID()
            tx.amount    = row.amount
            tx.category  = TransactionCategory.other.rawValue
            tx.type      = row.amount < 0 ? "expense" : "income"
            tx.date      = row.date
            tx.notes     = row.notes
            tx.createdAt = .now
            tx.account   = account
            account.balance += row.amount
        }

        try? ctx.save()
        HapticService.success()
        isImporting = false
        importState = .done(rows.count)
    }

    // MARK: - Sub-views

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: Theme.s8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.ledgerAccent)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statPill(value: String, label: String, color: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.monoSubhead().bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview Row

private struct PreviewRow: View {
    let row: ParsedRow

    var body: some View {
        HStack(spacing: Theme.s12) {
            Image(systemName: row.amount < 0 ? "minus.circle.fill" : "plus.circle.fill")
                .font(.body)
                .foregroundStyle(row.amount < 0 ? Color.ledgerNegative : Color.ledgerPositive)
                .opacity(row.isDuplicate ? 0.35 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.notes.isEmpty ? "—" : row.notes)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(row.isDuplicate ? .secondary : .primary)
                HStack(spacing: 4) {
                    Text(row.date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if row.isDuplicate {
                        Text("· already imported")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            Text(row.amount.asCurrency())
                .font(Theme.monoCaption())
                .foregroundStyle(row.isDuplicate ? Color.secondary : (row.amount < 0 ? Color.ledgerNegative : Color.ledgerPositive))
        }
        .padding(.vertical, Theme.s4)
    }
}

#Preview {
    let ctx = PersistenceController.preview.container.viewContext
    let account = try! ctx.fetch(Account.fetchRequest()).first!
    return CSVImportView(account: account)
        .environment(\.managedObjectContext, ctx)
}
