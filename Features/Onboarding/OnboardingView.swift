import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        .init(
            icon: "chart.line.uptrend.xyaxis",
            color: Color.ledgerAccent,
            title: "Net Worth at a Glance",
            body: "Dashboard shows your total balance, today's P&L, and a historical net worth chart with spending breakdown."
        ),
        .init(
            icon: "creditcard.fill",
            color: Color(red: 0.4, green: 0.6, blue: 1.0),
            title: "Track Every Account",
            body: "Add bank accounts, brokerages, and crypto wallets. Log transactions to keep balances accurate."
        ),
        .init(
            icon: "chart.pie.fill",
            color: Color.ledgerPositive,
            title: "Live Portfolio Prices",
            body: "Stocks, ETFs, and crypto pull live prices from Yahoo Finance so you always see your real portfolio value."
        ),
        .init(
            icon: "book.closed.fill",
            color: Color(red: 0.8, green: 0.5, blue: 0.2),
            title: "Trade Journal",
            body: "Log every trade with entry and exit prices, conviction rating, and strategy tags. Track your win rate over time."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Page content
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, p in
                    pageCard(p)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: .infinity)

            // MARK: Page indicators + button
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
                    Text(page == pages.count - 1 ? "Get Started" : "Next")
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
        VStack(spacing: Theme.s32) {
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
                Text(p.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(p.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
    let title: String
    let body:  String
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}
