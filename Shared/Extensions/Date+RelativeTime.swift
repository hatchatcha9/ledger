import Foundation

// MARK: - Custom notification names

extension Notification.Name {
    static let openBotsTab = Notification.Name("openBotsTab")
}

private let _isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    return f
}()

extension String {
    /// Converts an ISO-8601 UTC string → "just now", "5m ago", "2h ago", "3d ago".
    var relativeTimeAgo: String {
        guard let date = _isoFormatter.date(from: self) else { return self }
        let elapsed = -date.timeIntervalSinceNow
        switch elapsed {
        case ..<60:      return "just now"
        case ..<3600:    return "\(Int(elapsed / 60))m ago"
        case ..<86400:   return "\(Int(elapsed / 3600))h ago"
        default:         return "\(Int(elapsed / 86400))d ago"
        }
    }

    /// Converts an ISO-8601 UTC string to a `Date`, or `nil` if parsing fails.
    var iso8601Date: Date? { _isoFormatter.date(from: self) }
}
