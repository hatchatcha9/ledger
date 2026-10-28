import SwiftUI

// Horizontally-wrapping tag chip picker.
// Renders the tags in a flow layout using a LazyVGrid with auto-sizing columns.
struct FlowTagPicker: View {
    let allTags: [String]
    @Binding var selectedTags: Set<String>

    var body: some View {
        // Adaptive columns let chips wrap naturally.
        let columns = [GridItem(.adaptive(minimum: 80, maximum: 160), spacing: 8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(allTags, id: \.self) { tag in
                let selected = selectedTags.contains(tag)
                Button {
                    if selected { selectedTags.remove(tag) }
                    else        { selectedTags.insert(tag) }
                    HapticService.impact(.light)
                } label: {
                    Text(tag)
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            selected ? Color.ledgerAccent : Color(.secondarySystemFill),
                            in: Capsule()
                        )
                        .foregroundStyle(selected ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// Compact read-only display for transaction rows.
struct TagChips: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 4) {
                ForEach(tags.prefix(3), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.ledgerAccent.opacity(0.1), in: Capsule())
                        .foregroundStyle(Color.ledgerAccent)
                }
            }
        }
    }
}
