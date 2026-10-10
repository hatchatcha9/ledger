import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var inputText   = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // MARK: Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Theme.s12) {
                            if viewModel.messages.isEmpty {
                                emptyState
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }

                            ForEach(viewModel.messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: msg.isUser ? .trailing : .leading)
                                            .combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }

                            if viewModel.isLoading {
                                TypingIndicator()
                                    .id("typing")
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                            }

                            if let err = viewModel.errorMessage {
                                HStack(spacing: Theme.s8) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                    Text(err)
                                }
                                .font(.caption)
                                .foregroundStyle(.ledgerNegative)
                                .padding(.horizontal, Theme.s16)
                                .id("error")
                                .transition(.opacity)
                            }
                        }
                        .padding(Theme.s16)
                        .padding(.bottom, Theme.s8)
                        .animation(.spring(.smooth), value: viewModel.messages.count)
                        .animation(.spring(.smooth), value: viewModel.isLoading)
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in scrollToBottom(proxy: proxy) }
                    .onChange(of: viewModel.isLoading)     { _, _ in scrollToBottom(proxy: proxy) }
                }

                Divider()

                // MARK: Input bar
                HStack(spacing: Theme.s8) {
                    TextField("Ask about your finances or trades…", text: $inputText, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.plain)
                        .focused($inputFocused)
                        .padding(.horizontal, Theme.s12)
                        .padding(.vertical, Theme.s8)
                        .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
                        .onSubmit { sendIfReady() }

                    Button(action: sendIfReady) {
                        Image(systemName: viewModel.isLoading
                              ? "stop.circle.fill"
                              : "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(canSend ? Color.ledgerAccent : Color.secondary)
                            .scaleEffect(canSend ? 1.0 : 0.88)
                            .animation(.spring(.bouncy(duration: 0.22)), value: canSend)
                    }
                    .disabled(!canSend)
                }
                .padding(.horizontal, Theme.s12)
                .padding(.vertical, Theme.s8)
                .background(Color.ledgerGrouped)
            }
            .navigationTitle("Ask Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.messages.isEmpty {
                        Button {
                            HapticService.impact(.light)
                            withAnimation { viewModel.clearHistory() }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.ledgerNegative)
                        }
                    }
                }
            }
            // Lift input bar above keyboard — sheet already handles safe areas
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                inputFocused = true
            }
        }
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !viewModel.isLoading
    }

    private func sendIfReady() {
        guard canSend else { return }
        let text = inputText
        inputText = ""
        HapticService.impact(.light)
        Task { await viewModel.send(text) }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        let anchor: UnitPoint = .bottom
        if viewModel.isLoading {
            withAnimation(.spring(.smooth(duration: 0.3))) { proxy.scrollTo("typing", anchor: anchor) }
        } else if let last = viewModel.messages.last {
            withAnimation(.spring(.smooth(duration: 0.3))) { proxy.scrollTo(last.id, anchor: anchor) }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Theme.s16) {
            ZStack {
                Circle()
                    .fill(Color.ledgerAccent.opacity(0.08))
                    .frame(width: 72, height: 72)
                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.ledgerAccent)
            }

            VStack(spacing: Theme.s4) {
                Text("Ask anything")
                    .font(.title3.bold())
                Text("Your finances and trading bots are loaded in context.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Theme.s8) {
                suggestionChip("How's my portfolio performing?")
                suggestionChip("What's my savings rate this month?")
                suggestionChip("Should I switch crypto strategy?")
                suggestionChip("When will I hit my net worth goal?")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.s32)
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            HapticService.impact(.light)
            Task { await viewModel.send(text) }
        } label: {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.ledgerAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.s12)
                .padding(.vertical, Theme.s8)
                .background(Color.ledgerAccent.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: Theme.radiusM))
        }
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage

    // Parse markdown once; fall back to plain text if parsing fails.
    private var attributed: AttributedString {
        (try? AttributedString(
            markdown: message.text,
            options: .init(interpretedSyntax: .inlinesOnlyPreservingWhitespace)
        )) ?? AttributedString(message.text)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.s8) {
            if message.isUser { Spacer(minLength: 48) }

            if !message.isUser {
                ZStack {
                    Circle()
                        .fill(Color.ledgerAccent.opacity(0.12))
                        .frame(width: 26, height: 26)
                    Image(systemName: "sparkle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.ledgerAccent)
                }
            }

            Text(attributed)
                .font(.body)
                .foregroundStyle(message.isUser ? .white : .primary)
                .padding(.horizontal, Theme.s12)
                .padding(.vertical, Theme.s8)
                .background(
                    message.isUser ? Color.ledgerAccent : Color.ledgerSurface,
                    in: RoundedRectangle(cornerRadius: 18)
                )
                .textSelection(.enabled)

            if !message.isUser { Spacer(minLength: 48) }

            if message.isUser {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 26, height: 26)
                    Image(systemName: "person.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Typing indicator

private struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.s8) {
            ZStack {
                Circle()
                    .fill(Color.ledgerAccent.opacity(0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ledgerAccent)
            }

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                        .offset(y: animating ? -5 : 0)
                        .animation(
                            .interpolatingSpring(stiffness: 180, damping: 10)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.18),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, Theme.s12)
            .padding(.vertical, 14)
            .background(Color.ledgerSurface, in: RoundedRectangle(cornerRadius: 18))

            Spacer(minLength: 48)
        }
        .onAppear { animating = true }
    }
}

#Preview {
    ChatView(viewModel: {
        let vm = ChatViewModel()
        vm.messages = [
            ChatMessage(role: "user",      text: "How's my portfolio?"),
            ChatMessage(role: "assistant", text: "Your portfolio is up **12.3%** this month.\n\n- BTC: +18% (best performer)\n- ETH: +6.2%\n- SOL: -2.1%\n\nAll three bots are *HOLDING* on the 200-day trend filter."),
        ]
        return vm
    }())
}
