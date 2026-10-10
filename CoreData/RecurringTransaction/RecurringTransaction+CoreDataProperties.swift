import Foundation
import CoreData

extension RecurringTransaction {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<RecurringTransaction> {
        NSFetchRequest<RecurringTransaction>(entityName: "RecurringTransaction")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var amount: Double
    @NSManaged public var category: String?
    @NSManaged public var frequency: String?
    @NSManaged public var nextDueDate: Date?
    @NSManaged public var isActive: Bool
    @NSManaged public var notes: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var account: Account?
}

extension RecurringTransaction: Identifiable {}
