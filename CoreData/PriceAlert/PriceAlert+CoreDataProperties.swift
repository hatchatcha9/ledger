import Foundation
import CoreData

extension PriceAlert {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PriceAlert> {
        NSFetchRequest<PriceAlert>(entityName: "PriceAlert")
    }

    @NSManaged public var id:          UUID?
    @NSManaged public var symbol:      String?
    @NSManaged public var targetPrice: Double
    @NSManaged public var condition:   String?
    @NSManaged public var isActive:    Bool
    @NSManaged public var note:        String?
    @NSManaged public var createdAt:   Date?
}

extension PriceAlert: Identifiable {}
