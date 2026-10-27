import Foundation
import CoreData

// MARK: - Data types

struct ParsedRow: Identifiable {
    let id     = UUID()
    let date:  Date
    let notes: String
    let amount: Double          // negative = expense, positive = income
    var isDuplicate: Bool = false
}

struct CSVImportResult {
    let rows:          [ParsedRow]
    let unparsedCount: Int

    var newRows:       [ParsedRow] { rows.filter { !$0.isDuplicate } }
    var duplicateCount: Int        { rows.filter { $0.isDuplicate }.count }
}

// MARK: - Service

enum CSVImportService {

    // Parse a raw CSV string and flag duplicates against an account's transactions.
    static func parse(_ text: String, existingTransactions: [CDTransaction]) -> CSVImportResult {
        let lines = splitLines(text)
        guard !lines.isEmpty else { return CSVImportResult(rows: [], unparsedCount: 0) }

        let firstFields = parseFields(lines[0])
        let headerMap   = buildHeaderMap(firstFields)
        let dataLines   = headerMap != nil ? Array(lines.dropFirst()) : lines

        var parsed:   [ParsedRow] = []
        var unparsed  = 0

        for line in dataLines {
            let fields = parseFields(line)
            guard !fields.allSatisfy({ $0.isEmpty }) else { continue }
            if let row = extractRow(fields: fields, headerMap: headerMap) {
                parsed.append(row)
            } else {
                unparsed += 1
            }
        }

        let marked = markDuplicates(parsed, against: existingTransactions)
        return CSVImportResult(rows: marked, unparsedCount: unparsed)
    }

    // MARK: - Header detection

    private struct HeaderMap {
        var dateIndex:   Int
        var amountIndex: Int?
        var debitIndex:  Int?
        var creditIndex: Int?
        var notesIndex:  Int
    }

    private static func buildHeaderMap(_ fields: [String]) -> HeaderMap? {
        let lower = fields.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        let dateKeys   = ["date", "transaction date", "trans date", "posted date",
                          "settlement date", "value date", "posting date",
                          "activity date", "process date"]   // Robinhood
        let amtKeys    = ["amount", "transaction amount", "net amount"]
        let debitKeys  = ["debit", "debit amount", "withdrawals", "withdrawal"]
        let creditKeys = ["credit", "credit amount", "deposits", "deposit"]
        let notesKeys  = ["description", "merchant", "name", "payee", "memo",
                          "narrative", "details", "transaction description",
                          "particulars", "reference",
                          "instrument"]   // Robinhood (ticker symbol column)

        guard let dateIdx  = lower.firstIndex(where: { dateKeys.contains($0) }),
              let notesIdx = lower.firstIndex(where: { notesKeys.contains($0) })
        else { return nil }

        let amtIdx    = lower.firstIndex(where: { amtKeys.contains($0) })
        let debitIdx  = lower.firstIndex(where: { debitKeys.contains($0) })
        let creditIdx = lower.firstIndex(where: { creditKeys.contains($0) })

        // Need at least one amount column
        guard amtIdx != nil || (debitIdx != nil && creditIdx != nil) else { return nil }

        return HeaderMap(dateIndex: dateIdx, amountIndex: amtIdx,
                         debitIndex: debitIdx, creditIndex: creditIdx,
                         notesIndex: notesIdx)
    }

    // MARK: - Row extraction

    private static func extractRow(fields: [String], headerMap: HeaderMap?) -> ParsedRow? {
        if let hm = headerMap {
            return extractWithMap(fields: fields, map: hm)
        } else {
            return extractPositional(fields: fields)
        }
    }

    private static func extractWithMap(fields: [String], map: HeaderMap) -> ParsedRow? {
        guard map.dateIndex < fields.count, map.notesIndex < fields.count else { return nil }
        guard let date = parseDate(fields[map.dateIndex]) else { return nil }
        let notes = fields[map.notesIndex].trimmingCharacters(in: .whitespaces)

        let amount: Double
        if let ai = map.amountIndex, ai < fields.count {
            guard let a = parseAmount(fields[ai]) else { return nil }
            amount = a
        } else if let di = map.debitIndex, let ci = map.creditIndex,
                  di < fields.count, ci < fields.count {
            let debit  = parseAmount(fields[di]) ?? 0
            let credit = parseAmount(fields[ci]) ?? 0
            if debit == 0 && credit == 0 { return nil }
            // Debit = money leaving the account = negative
            amount = credit - debit
        } else { return nil }

        return ParsedRow(date: date, notes: notes, amount: amount)
    }

    // Positional fallback for header-less formats (e.g. Wells Fargo).
    // Expects: Date, Amount, ..., Description (last field)
    private static func extractPositional(fields: [String]) -> ParsedRow? {
        guard fields.count >= 3 else { return nil }
        guard let date   = parseDate(fields[0]),
              let amount = parseAmount(fields[1]) else { return nil }
        let notes = fields.last?.trimmingCharacters(in: .whitespaces) ?? ""
        return ParsedRow(date: date, notes: notes, amount: amount)
    }

    // MARK: - Duplicate detection

    private static func markDuplicates(_ rows: [ParsedRow],
                                       against existing: [CDTransaction]) -> [ParsedRow] {
        var result = rows
        let cal = Calendar.current
        for i in result.indices {
            let r = result[i]
            result[i].isDuplicate = existing.contains { tx in
                guard let txDate = tx.date else { return false }
                return cal.isDate(txDate, inSameDayAs: r.date)
                    && abs(tx.amount - r.amount) < 0.005
                    && tx.wrappedNotes.lowercased() == r.notes.lowercased()
            }
        }
        return result
    }

    // MARK: - Date parsing

    private static let dateFormats = [
        "MM/dd/yyyy", "M/d/yyyy",
        "yyyy-MM-dd",
        "dd/MM/yyyy", "d/M/yyyy",
        "MM-dd-yyyy", "yyyy/MM/dd",
        "d MMM yyyy", "dd MMM yyyy",
        "MMM dd, yyyy", "MMM d, yyyy",
        "dd-MMM-yyyy",
    ]

    static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in dateFormats {
            f.dateFormat = fmt
            if let d = f.date(from: trimmed) { return d }
        }
        return nil
    }

    // MARK: - Amount parsing

    static func parseAmount(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        // Parentheses = accounting negative: (12.50) → -12.50
        let negative = s.hasPrefix("(") && s.hasSuffix(")")
        s = s.replacingOccurrences(of: "(", with: "")
             .replacingOccurrences(of: ")", with: "")
             .replacingOccurrences(of: "$", with: "")
             .replacingOccurrences(of: "£", with: "")
             .replacingOccurrences(of: "€", with: "")
             .replacingOccurrences(of: "¥", with: "")
             .replacingOccurrences(of: "₹", with: "")
             .replacingOccurrences(of: ",", with: "")
             .replacingOccurrences(of: " ", with: "")

        guard let value = Double(s) else { return nil }
        return negative ? -abs(value) : value
    }

    // MARK: - CSV helpers

    static func splitLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r",   with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // RFC 4180-compliant field parser.
    static func parseFields(_ line: String) -> [String] {
        var fields:   [String] = []
        var current   = ""
        var inQuotes  = false
        var i         = line.startIndex

        while i < line.endIndex {
            let ch = line[i]
            if inQuotes {
                if ch == "\"" {
                    let next = line.index(after: i)
                    if next < line.endIndex && line[next] == "\"" {
                        current.append("\"")        // escaped quote
                        i = line.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(ch)
                }
            } else {
                switch ch {
                case "\"": inQuotes = true
                case ",":
                    fields.append(current)
                    current = ""
                default:
                    current.append(ch)
                }
            }
            i = line.index(after: i)
        }
        fields.append(current)
        return fields
    }
}
