import Foundation
import CoreData

extension CDTransaction {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTransaction> {
        NSFetchRequest<CDTransaction>(entityName: "CDTransaction")
    }

    @NSManaged public var id:         UUID?
    @NSManaged public var amount:     Double
    @NSManaged public var category:   String?
    @NSManaged public var type:       String?
    @NSManaged public var date:       Date?
    @NSManaged public var notes:      String?
    @NSManaged public var createdAt:  Date?
    @NSManaged public var splitsJSON: String?
    @NSManaged public var tagsRaw:    String?

    // Inverse relationship back to the owning account.
    @NSManaged public var account: Account?
}

extension CDTransaction: Identifiable {}
