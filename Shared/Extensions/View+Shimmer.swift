import SwiftUI

// Shared shimmer overlay for skeleton loading states.
// Use `.shimmering()` on any view — applies a sweeping gradient highlight.
extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear,               location: 0),
                            .init(color: .white.opacity(0.32), location: 0.45),
                            .init(color: .white.opacity(0.32), location: 0.55),
                            .init(color: .clear,               location: 1),
                        ]),
                        startPoint: .init(x: phase - 0.3, y: 0),
                        endPoint:   .init(x: phase + 0.3, y: 0)
                    )
                    .blendMode(.plusLighter)
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}
