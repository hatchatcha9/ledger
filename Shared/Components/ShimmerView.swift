import SwiftUI

// Skeleton shimmer placeholder for loading states.
// Shows a sweeping highlight over a rounded rectangle background.
struct ShimmerView: View {
    var height: CGFloat = 14
    var cornerRadius: CGFloat = 6

    @State private var animating = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.tertiarySystemFill))
            .frame(height: height)
            .overlay(shimmerHighlight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onAppear { animating = true }
    }

    private var shimmerHighlight: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.38), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 120)
        .offset(x: animating ? 600 : -300)
        .blendMode(.screen)
        .animation(
            .linear(duration: 1.3).repeatForever(autoreverses: false),
            value: animating
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        ShimmerView(height: 20)
            .frame(width: 100)
        ShimmerView(height: 14)
            .frame(width: 60)
    }
    .padding()
    .background(Color(.secondarySystemBackground))
}
