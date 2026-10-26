import SwiftUI

/// Compact sentiment pill — shows nothing if data is nil.
struct SentimentBadge: View {
    let data: SentimentData?

    var body: some View {
        if let d = data {
            HStack(spacing: 3) {
                Image(systemName: d.label.icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(d.label.rawValue)
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(d.label.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(d.label.color.opacity(0.12), in: Capsule())
        }
    }
}
