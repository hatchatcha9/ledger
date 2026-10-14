import SwiftUI

// MARK: - Semantic Colors
// Defined in Swift so they work without an Asset Catalog on first run.
// Once you add named colors to Assets.xcassets, swap these for Color("name").
extension Color {
    static let ledgerAccent   = Color(red: 0.0,   green: 0.478, blue: 1.0)
    static let ledgerPositive = Color(red: 0.196, green: 0.796, blue: 0.384)
    static let ledgerNegative = Color(red: 1.0,   green: 0.231, blue: 0.188)
    static let ledgerSurface  = Color(.secondarySystemBackground)
    static let ledgerGrouped  = Color(.systemGroupedBackground)
}

// Allows .ledgerAccent / .ledgerPositive / .ledgerNegative in foregroundStyle() contexts.
extension ShapeStyle where Self == Color {
    static var ledgerAccent:   Color { Color(red: 0.0,   green: 0.478, blue: 1.0) }
    static var ledgerPositive: Color { Color(red: 0.196, green: 0.796, blue: 0.384) }
    static var ledgerNegative: Color { Color(red: 1.0,   green: 0.231, blue: 0.188) }
}

// MARK: - Design Tokens
enum Theme {
    // Spacing — multiples of 4 pt (standard iOS grid)
    static let s4:  CGFloat = 4
    static let s8:  CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32

    // Corner radii
    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 12
    static let radiusL: CGFloat = 16

    // Typography helpers — monospaced for numbers so digits don't shift width
    static func monoBody()        -> Font { .system(.body,        design: .monospaced) }
    static func monoSubhead()     -> Font { .system(.subheadline, design: .monospaced) }
    static func monoCaption()     -> Font { .system(.caption,     design: .monospaced) }
    static func monoTitle2()      -> Font { .system(.title2,      design: .monospaced).bold() }
    static func monoLargeTitle()  -> Font { .system(.largeTitle,  design: .monospaced).bold() }
}

// MARK: - Button Styles

// Applies a subtle scale-down on press for tactile press feedback.
struct ScaleButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

// MARK: - Change color helper
// Returns .ledgerPositive for gains, .ledgerNegative for losses, .secondary for zero.
extension Color {
    static func changeColor(for value: Double) -> Color {
        if value > 0 { return .ledgerPositive }
        if value < 0 { return .ledgerNegative }
        return Color(.secondaryLabel)
    }
}

// MARK: - Currency formatting
extension Double {
    /// "$12,450.00" — uses the device locale's currency symbol.
    func asCurrency(code: String = "USD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.string(from: NSNumber(value: self)) ?? "$0.00"
    }

    /// "+3.42%" or "-1.05%"
    func asChangePercent() -> String {
        let sign = self >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", self))%"
    }
}
