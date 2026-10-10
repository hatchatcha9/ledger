import Foundation
import CoreData

extension JournalEntry {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<JournalEntry> {
        NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var symbol: String?
    @NSManaged public var direction: String?
    // Int16 scalar — stored as a 1–5 conviction rating in the UI.
    @NSManaged public var conviction: Int16
    @NSManaged public var strategyTag: String?
    @NSManaged public var entryPrice: Double
    @NSManaged public var exitPrice: Double
    @NSManaged public var entryDate: Date?
    @NSManaged public var exitDate: Date?
    @NSManaged public var outcome: String?
    @NSManaged public var notes: String?
    @NSManaged public var createdAt: Date?
}

extension JournalEntry: Identifiable {}
