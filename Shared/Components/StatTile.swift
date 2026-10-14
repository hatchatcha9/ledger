import SwiftUI

// A card that shows one key metric with a label and an optional change indicator.
// Used on the Dashboard (net worth, today's P&L) and the Portfolio screen.
//
// Usage:
//   StatTile(label: "Net Worth", value: "$12,450", change: "+3.2%", changePositive: true)
struct StatTile: View {
    let label: String
    let value: String
    var change: String? = nil
    var changePositive: Bool? = nil  // nil = neutral (grey)
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s8) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(value)
                .font(Theme.monoTitle2())
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)

            if let change {
                HStack(spacing: 4) {
                    if let positive = changePositive {
                        Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2)
                    }
                    Text(change)
                        .font(.caption)
                }
                .foregroundStyle(changeColor)
            }
        }
        .padding(Theme.s16)
        .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
    }

    private var changeColor: Color {
        switch changePositive {
        case true:  return .ledgerPositive
        case false: return .ledgerNegative
        default:    return Color(.secondaryLabel)
        }
    }
}

// MARK: - Preview
#Preview("Positive change") {
    StatTile(
        label: "Net Worth",
        value: "$15,650.00",
        change: "+3.42%",
        changePositive: true,
        icon: "chart.line.uptrend.xyaxis"
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Negative change") {
    StatTile(
        label: "Today's P&L",
        value: "-$120.00",
        change: "-0.85%",
        changePositive: false
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
