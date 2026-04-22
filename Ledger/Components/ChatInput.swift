import SwiftUI
import UIKit

struct ChatInput: View {
    private let isUITestMode = ProcessInfo.processInfo.environment["LEDGER_TEST_MODE"] == "1"

    @Binding var draft: String
    let onSend: (String) -> Void

    @State private var isRecording = false
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.ledgerHairline)
                .frame(height: 1)

            HStack(alignment: .bottom, spacing: 12) {
                TextField(
                    "",
                    text: $draft,
                    prompt: Text("Message").foregroundStyle(Color.ledgerTextTertiary),
                    axis: .vertical
                )
                .font(Typography.serifBody(17))
                .foregroundStyle(Color.ledgerTextPrimary)
                .tint(Color.ledgerTextPrimary)
                .lineLimit(1...5)
                .onSubmit(sendIfPossible)
                .onChange(of: draft) { _, newValue in
                    guard isUITestMode, newValue.contains("\n") else { return }
                    draft = newValue.replacingOccurrences(of: "\n", with: "")
                    sendIfPossible()
                }
                .submitLabel(.send)
                .accessibilityIdentifier("chat.input")

                micButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.ledgerBg)
        }
    }

    private var micButton: some View {
        Button(action: handlePrimaryAction) {
            ZStack {
                Circle()
                    .fill(Color.ledgerTextPrimary)
                    .frame(width: 44, height: 44)
                    .scaleEffect(isRecording ? (pulse ? 1.12 : 1.0) : (draft.isEmpty ? 1.0 : 0.98))

                Image(systemName: draft.isEmpty ? "mic.fill" : "arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.ledgerBg)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: pulse)
        .contentShape(Circle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.25)
                .onEnded { _ in
                    if draft.isEmpty {
                        startRecording()
                    }
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    if isRecording { stopRecording() }
                }
        )
        .accessibilityIdentifier("chat.sendButton")
    }

    private func sendIfPossible() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hapticLight()
        onSend(trimmed)
        draft = ""
    }

    private func handlePrimaryAction() {
        if draft.isEmpty {
            hapticLight()
        } else {
            sendIfPossible()
        }
    }

    private func startRecording() {
        hapticLight()
        withAnimation(.easeInOut(duration: 0.15)) {
            isRecording = true
        }
        pulse = true
    }

    private func stopRecording() {
        pulse = false
        withAnimation(.easeInOut(duration: 0.15)) {
            isRecording = false
        }
    }

    private func hapticLight() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}
