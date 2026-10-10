import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    // In-memory store for Xcode Previews — never touches disk.
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let ctx = controller.container.viewContext
        seedPreviewData(into: ctx)
        return controller
    }()

    let container: NSPersistentCloudKitContainer

    // App Group used to share the SQLite store with the widget extension.
    // Change this to match the group ID in Xcode → Signing & Capabilities.
    static let appGroupID = "group.ledger"

    // CloudKit container identifier — must match the iCloud container you
    // add in Xcode → Signing & Capabilities → iCloud → CloudKit.
    static let cloudKitContainerID = "iCloud.com.hatchatcha9.ledger"

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Ledger")

        if inMemory {
            // Previews: in-memory store, no CloudKit sync.
            let desc = NSPersistentStoreDescription()
            desc.url = URL(fileURLWithPath: "/dev/null")
            desc.cloudKitContainerOptions = nil
            container.persistentStoreDescriptions = [desc]
        } else if let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)?
            .appendingPathComponent("Ledger.sqlite") {
            let desc = NSPersistentStoreDescription(url: groupURL)
            // Enable CloudKit sync.
            let ckOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerID
            )
            desc.cloudKitContainerOptions = ckOptions
            // Required for CloudKit mirroring and remote-change notifications.
            desc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            desc.setOption(true as NSNumber,
                           forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            container.persistentStoreDescriptions = [desc]
        }

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Core Data failed to load: \(error.localizedDescription)")
            }
        }

        // Merge remote CloudKit changes into the view context automatically.
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Save helper
    // Call this after any batch of mutations; the view context is saved on the
    // main queue so no concurrency issues.
    func save() {
        let ctx = container.viewContext
        guard ctx.hasChanges else { return }
        do {
            try ctx.save()
        } catch {
            // Surface the error properly in a real app.
            print("Core Data save error: \(error)")
        }
    }
}

// MARK: - Preview seed
private func seedPreviewData(into ctx: NSManagedObjectContext) {
    // Brokerage account
    let brokerage = Account(context: ctx)
    brokerage.id = UUID()
    brokerage.name = "Fidelity Brokerage"
    brokerage.type = AccountType.brokerage.rawValue
    brokerage.balance = 12_450.00
    brokerage.currency = "USD"
    brokerage.createdAt = .now

    // Crypto wallet
    let wallet = Account(context: ctx)
    wallet.id = UUID()
    wallet.name = "Ledger Nano"
    wallet.type = AccountType.cryptoWallet.rawValue
    wallet.balance = 3_200.00
    wallet.currency = "USD"
    wallet.createdAt = .now

    // A few sample transactions on the brokerage account
    let categories: [(String, TransactionCategory, Double)] = [
        ("Coffee", .food, -6.50),
        ("Dividend — AAPL", .dividends, 18.75),
        ("Trade fee", .tradeFee, -4.95),
    ]
    for (notes, cat, amount) in categories {
        let tx = CDTransaction(context: ctx)
        tx.id = UUID()
        tx.amount = amount
        tx.category = cat.rawValue
        tx.type = amount < 0 ? "expense" : "income"
        tx.date = Date(timeIntervalSinceNow: Double.random(in: -86400 * 7 ... 0))
        tx.notes = notes
        tx.createdAt = .now
        tx.account = brokerage
    }

    // A sample asset
    let btc = Asset(context: ctx)
    btc.id = UUID()
    btc.symbol = "BTC"
    btc.name = "Bitcoin"
    btc.quantity = 0.05
    btc.avgCost = 55_000
    btc.assetType = AssetType.crypto.rawValue
    btc.account = wallet

    // A journal entry
    let entry = JournalEntry(context: ctx)
    entry.id = UUID()
    entry.symbol = "BTC"
    entry.direction = "long"
    entry.conviction = 4
    entry.strategyTag = "trend-follow"
    entry.entryPrice = 58_000
    entry.entryDate = Date(timeIntervalSinceNow: -86400 * 3)
    entry.outcome = TradeOutcome.open.rawValue
    entry.notes = "Breakout above 200-day MA, volume confirming."
    entry.createdAt = .now

    try? ctx.save()
}
