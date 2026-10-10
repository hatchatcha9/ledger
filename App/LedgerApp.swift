import SwiftUI

@main
struct LedgerApp: App {
    let persistence = PersistenceController.shared
    @StateObject private var prices      = PriceService()
    @StateObject private var alertsSvc   = PriceAlertsService()
    @StateObject private var authGate    = AuthGate()
    #if DEBUG
    @StateObject private var quantStatus = QuantStatusService()
    #endif

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if authGate.isUnlocked {
                    ContentView()
                        .environment(\.managedObjectContext, persistence.container.viewContext)
                        .environmentObject(prices)
                        .environmentObject(alertsSvc)
                        #if DEBUG
                        .environmentObject(quantStatus)
                        #endif
                } else {
                    LockView()
                }
            }
            .environmentObject(authGate)
            // Lock when app moves to background; re-authenticate on return.
            // Also run recurring catch-up every time the app becomes active so
            // transactions post even if the app was backgrounded for days.
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    authGate.lock()
                case .active:
                    Task { await authGate.authenticate() }
                    let bgCtx = persistence.container.newBackgroundContext()
                    bgCtx.perform { RecurringService.generateDue(in: bgCtx) }
                default:
                    break
                }
            }
        }
    }
}
