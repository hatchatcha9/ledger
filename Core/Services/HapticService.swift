import UIKit

enum HapticService {
    private static let notification = UINotificationFeedbackGenerator()
    private static let selection    = UISelectionFeedbackGenerator()
    private static let light        = UIImpactFeedbackGenerator(style: .light)
    private static let medium       = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy        = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigid        = UIImpactFeedbackGenerator(style: .rigid)
    private static let soft         = UIImpactFeedbackGenerator(style: .soft)

    static func success() {
        notification.prepare()
        notification.notificationOccurred(.success)
    }

    static func error() {
        notification.prepare()
        notification.notificationOccurred(.error)
    }

    static func warning() {
        notification.prepare()
        notification.notificationOccurred(.warning)
    }

    /// Use for picker/filter/tab changes.
    static func select() {
        selection.prepare()
        selection.selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let gen: UIImpactFeedbackGenerator
        switch style {
        case .light:  gen = light
        case .heavy:  gen = heavy
        case .rigid:  gen = rigid
        case .soft:   gen = soft
        default:      gen = medium
        }
        gen.prepare()
        gen.impactOccurred()
    }
}
