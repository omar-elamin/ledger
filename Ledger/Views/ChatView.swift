import SwiftUI
import SwiftData

@MainActor
struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ChatViewModel
    @State private var draft: String = ""

    init(viewModel: ChatViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 8).id("top")
                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                        MessageBubble(
                            message: message,
                            isClusterStart: isClusterStart(at: index)
                        )
                        .id(message.id)
                        .accessibilityIdentifier("chat.messageBubble.\(message.role.rawValue)")
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 10)),
                                removal: .identity
                            )
                        )
                    }
                    if shouldShowStreamingResponse {
                        VStack(alignment: .leading, spacing: 0) {
                            if let streamingMessage = viewModel.streamingMessage,
                               !streamingMessage.content.isEmpty {
                                MessageBubble(
                                    message: streamingMessage,
                                    isClusterStart: isStreamingClusterStart(role: streamingMessage.role)
                                )
                            }

                            if let activityStatus = viewModel.activityStatus {
                                ChatActivityStatusView(
                                    text: activityStatus,
                                    isClusterStart: !hasVisibleStreamingMessage && isStreamingClusterStart(role: .coach)
                                )
                            }
                        }
                        .id("streamingResponse")
                        .accessibilityIdentifier("chat.streamingBubble")
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 10)),
                                removal: .identity
                            )
                        )
                    }
                    Color.clear.frame(height: 36).id("bottom")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .accessibilityIdentifier("chat.messageList")
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .background(Color.ledgerBg)
            .onAppear {
                viewModel.loadInitialMessages(from: modelContext)
                scrollToBottom(proxy: proxy, animated: false)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onChange(of: viewModel.streamingMessage?.content) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onChange(of: viewModel.activityStatus) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ChatInput(draft: $draft) { text in
                    viewModel.send(text, modelContext: modelContext)
                }
            }
        }
    }

    private func isClusterStart(at index: Int) -> Bool {
        guard index > 0 else { return true }
        return viewModel.messages[index - 1].role != viewModel.messages[index].role
    }

    private var shouldShowStreamingResponse: Bool {
        hasVisibleStreamingMessage || viewModel.activityStatus != nil
    }

    private var hasVisibleStreamingMessage: Bool {
        guard let streamingMessage = viewModel.streamingMessage else { return false }
        return !streamingMessage.content.isEmpty
    }

    private func isStreamingClusterStart(role: MessageRole) -> Bool {
        guard let last = viewModel.messages.last else { return true }
        return last.role != role
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        let action = { proxy.scrollTo("bottom", anchor: .bottom) }
        if animated {
            withAnimation(.smooth(duration: 0.35)) { action() }
        } else {
            action()
        }
    }
}

private struct ChatActivityStatusView: View {
    let text: String
    var isClusterStart: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(text)
                    .font(Typography.serifBody(15))
                    .foregroundStyle(Color.ledgerTextTertiary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.82, alignment: .leading)

            Spacer(minLength: 40)
        }
        .padding(.top, isClusterStart ? 18 : 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityIdentifier("chat.activityStatus")
    }
}
