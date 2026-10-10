import Foundation
import CoreData
import UserNotifications
import UIKit

// Checks active PriceAlert records against the latest prices from PriceService
// and fires a local notification when a threshold is crossed.
@MainActor
final class PriceAlertsService: ObservableObject {

    func checkAndFire(prices: [String: Double], in ctx: NSManagedObjectContext) {
        let req = PriceAlert.fetchRequest()
        req.predicate = NSPredicate(format: "isActive == YES")
        guard let alerts = try? ctx.fetch(req), !alerts.isEmpty else { return }

        var didChange = false
        for alert in alerts {
            guard let currentPrice = prices[alert.wrappedSymbol] else { continue }
            if alert.isTriggered(by: currentPrice) {
                scheduleNotification(for: alert, currentPrice: currentPrice)
                alert.isActive = false
                didChange = true
            }
        }
        if didChange {
            try? ctx.save()
            HapticService.success()
        }
    }

    private func scheduleNotification(for alert: PriceAlert, currentPrice: Double) {
        let content        = UNMutableNotificationContent()
        content.title      = "📊 \(alert.wrappedSymbol) Price Alert"
        let dir            = alert.alertCondition == .above ? "above" : "below"
        let note           = alert.wrappedNote.isEmpty ? "" : " — \(alert.wrappedNote)"
        content.body       = "\(alert.wrappedSymbol) hit \(currentPrice.asCurrency()) (\(dir) your \(alert.targetPrice.asCurrency()) target)\(note)"
        content.sound      = .default
        content.categoryIdentifier = "PRICE_ALERT"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let id      = "price-alert-\(alert.objectID.uriRepresentation().absoluteString.hashValue)"
        let req     = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }
}
