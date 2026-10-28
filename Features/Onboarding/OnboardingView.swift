import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        .init(
            icon:     "hand.wave.fill",
            color:    Color.ledgerAccent,
            step:     nil,
            title:    "Welcome to Ledger",
            body:     "Your finances, owned by you. No subscription. No cloud. Your data stays on your device.\n\nHere's exactly what to do first."
        ),
        .init(
            icon:     "creditcard.fill",
            color:    Color(red: 0.4, green: 0.6, blue: 1.0),
            step:     "Step 1 of 3",
            title:    "Add an Account",
            body:     "Tap the Accounts tab → + button. Add your checking account, savings, or brokerage. Give it a starting balance.\n\nDon't worry about being exact — you can adjust it anytime."
        ),
        .init(
            icon:     "arrow.down.doc.fill",
            color:    Color.ledgerPositive,
            step:     "Step 2 of 3",
            title:    "Import Your Transactions",
            body:     "Open any account → tap ··· → Import CSV. Export a statement from your bank's website and drop it in.\n\nWorks with Chase, Bank of America, Wells Fargo, Citi, and most standard exports. Duplicates are caught automatically."
        ),
        .init(
            icon:     "chart.line.uptrend.xyaxis",
            color:    Color(red: 0.8, green: 0.5, blue: 0.2),
            step:     "Step 3 of 3",
            title:    "Your Dashboard Unlocks",
            body:     "After a few months of data you'll see your FI/RE progress, spending velocity alerts, emergency fund meter, and an AI analysis of your actual finances.\n\nThe more data you add, the smarter it gets."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Skip button
            HStack {
                Spacer()
                Button("Skip") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    isPresented = false
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.s24)
                .padding(.top, Theme.s16)
            }

            // Page content
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, p in
                    pageCard(p)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: .infinity)

            // Page indicators + button
            VStack(spacing: Theme.s24) {
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Color.ledgerAccent : Color(.tertiaryLabel))
                            .frame(width: i == page ? 20 : 8, height: 8)
                            .animation(.spring(response: 0.3), value: page)
                    }
                }

                Button(action: advance) {
                    Text(page == pages.count - 1 ? "Let's Go" : "Next")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.ledgerAccent)
                .controlSize(.large)
                .padding(.horizontal, Theme.s32)
            }
            .padding(.bottom, Theme.s32)
        }
    }

    @ViewBuilder
    private func pageCard(_ p: OnboardingPage) -> some View {
        VStack(spacing: Theme.s24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(p.color.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: p.icon)
                    .font(.system(size: 52))
                    .foregroundStyle(p.color)
            }

            VStack(spacing: Theme.s12) {
                if let step = p.step {
                    Text(step)
                        .font(.caption.bold())
                        .foregroundStyle(p.color)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(p.color.opacity(0.12), in: Capsule())
                }

                Text(p.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(p.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
            .padding(.horizontal, Theme.s32)

            Spacer()
            Spacer()
        }
    }

    private func advance() {
        if page < pages.count - 1 {
            withAnimation { page += 1 }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            isPresented = false
        }
    }
}

private struct OnboardingPage {
    let icon:  String
    let color: Color
    let step:  String?
    let title: String
    let body:  String
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}
