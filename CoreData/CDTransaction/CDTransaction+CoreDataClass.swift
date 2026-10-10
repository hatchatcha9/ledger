import Foundation
import CoreData

// Named CDTransaction (not Transaction) because Swift 5.5+ reserves "Transaction"
// for the Transactions concurrency API in the standard library.
@objc(CDTransaction)
public class CDTransaction: NSManagedObject {}
