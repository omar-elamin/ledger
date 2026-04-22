import SwiftUI

struct MessageBubble: View {
    let message: Message
    var isClusterStart: Bool = true

    @State private var showTimestamp = false
    @State private var hideTask: Task<Void, Never>?

    private var isUser: Bool { message.role == .user }

    private var timestampString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: message.timestamp)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                Text(message.content)
                    .font(Typography.serifBody(17))
                    .foregroundStyle(isUser ? Color.ledgerTextSecondary : Color.ledgerTextPrimary)
                    .lineSpacing(4)
                    .multilineTextAlignment(isUser ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .onLongPressGesture(minimumDuration: 0.3) {
                        reveal()
                    }

                if showTimestamp {
                    Text(timestampString)
                        .font(Typography.roundedNumber(11))
                        .foregroundStyle(Color.ledgerTextTertiary)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * (isUser ? 0.55 : 0.82),
                   alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.top, isClusterStart ? 18 : 4)
    }

    private func reveal() {
        hideTask?.cancel()
        withAnimation(.smooth(duration: 0.2)) {
            showTimestamp = true
        }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.smooth(duration: 0.3)) {
                        showTimestamp = false
                    }
                }
            }
        }
    }
}
