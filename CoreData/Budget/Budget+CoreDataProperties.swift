import Foundation
import CoreData

extension Budget {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Budget> {
        NSFetchRequest<Budget>(entityName: "Budget")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var category: String?
    @NSManaged public var monthlyLimit: Double
    @NSManaged public var createdAt: Date?
}

extension Budget: Identifiable {}
