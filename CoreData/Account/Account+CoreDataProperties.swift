import Foundation
import CoreData

extension Account {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Account> {
        NSFetchRequest<Account>(entityName: "Account")
    }

    // Scalar types (Double, Bool, Int) skip the Optional wrapper and use their
    // zero value as default — matches the "usesScalarValueType" flag in the model.
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var type: String?
    @NSManaged public var balance: Double
    @NSManaged public var currency: String?
    @NSManaged public var createdAt: Date?

    // To-many relationships come back as NSSet; we unwrap them in Extensions.
    @NSManaged public var transactions: NSSet?
    @NSManaged public var assets: NSSet?
    @NSManaged public var recurringTransactions: NSSet?
}

// Conforming to Identifiable lets us use Account in SwiftUI ForEach without .id().
extension Account: Identifiable {}
