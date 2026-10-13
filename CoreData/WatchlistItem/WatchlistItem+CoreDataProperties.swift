import Foundation
import CoreData

extension WatchlistItem {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<WatchlistItem> {
        NSFetchRequest<WatchlistItem>(entityName: "WatchlistItem")
    }

    @NSManaged public var id:          UUID?
    @NSManaged public var symbol:      String?
    @NSManaged public var name:        String?
    @NSManaged public var assetType:   String?
    @NSManaged public var addedAt:     Date?
    @NSManaged public var thesis:      String?
    @NSManaged public var targetPrice: Double
}

extension WatchlistItem: Identifiable {}
