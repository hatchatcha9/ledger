import Foundation
import CoreData

extension Asset {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Asset> {
        NSFetchRequest<Asset>(entityName: "Asset")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var symbol: String?
    @NSManaged public var name: String?
    @NSManaged public var quantity: Double
    @NSManaged public var avgCost: Double
    @NSManaged public var assetType: String?

    @NSManaged public var account: Account?
}

extension Asset: Identifiable {}
