import SwiftUI
import StoreKit

// Root of the app. Each tab owns its own NavigationStack so the back-stack
// is independent per tab — standard iOS pattern.
struct ContentView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.requestReview) private var requestReview
    @EnvironmentObject private var priceService: PriceService
    @EnvironmentObject private var alertsSvc:    PriceAlertsService
    @AppStorage("hasSeenOnboarding")       private var hasSeenOnboarding = false
    @AppStorage("txCountAtLastReview")     private var txCountAtLastReview = 0
    @State private var showOnboarding = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tag(0)
                .tabItem {
                    Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis")
                }

            AccountsView()
                .tabItem { Label("Accounts", systemImage: "creditcard") }
                .tag(1)

            PortfolioView()
                .tabItem { Label("Portfolio", systemImage: "chart.pie.fill") }
                .tag(2)

            JournalView()
                .tabItem { Label("Journal", systemImage: "book.closed.fill") }
                .tag(3)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(4)
        }
        .tint(Color.ledgerAccent)
        .onChange(of: priceService.prices) { _, newPrices in
            alertsSvc.checkAndFire(prices: newPrices, in: ctx)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
                .onDisappear { hasSeenOnboarding = true }
        }
        .onAppear {
            if !hasSeenOnboarding { showOnboarding = true }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: ctx)
        ) { _ in
            let req = CDTransaction.fetchRequest()
            let count = (try? ctx.count(for: req)) ?? 0
            // Request a review after the 5th transaction, then again every 20 after that.
            // Apple throttles actual prompts to ~3 per year regardless.
            if count >= 5 && count - txCountAtLastReview >= 20 || (count >= 5 && txCountAtLastReview == 0) {
                txCountAtLastReview = count
                Task { @MainActor in requestReview() }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environmentObject(PriceService())
        .environmentObject(PriceAlertsService())
        .environmentObject(QuantStatusService())
}
