import Foundation
@testable import Ledger

actor StubStreamingClient: CoachStreamingClient {
    nonisolated let hasAPIKeyConfigured: Bool

    private var scripts: [Script]
    private(set) var invocations: [Invocation] = []
    private(set) var completedToolUses: [CompletedToolUse] = []

    init(
        hasAPIKeyConfigured: Bool = true,
        scripts: [Script]
    ) {
        self.hasAPIKeyConfigured = hasAPIKeyConfigured
        self.scripts = scripts
    }

    func streamMessage(
        messages: [Message],
        contextBlock: String,
        tools: [Tool]
    ) async -> AsyncThrowingStream<StreamEvent, Error> {
        invocations.append(
            Invocation(
                messages: messages,
                contextBlock: contextBlock,
                tools: tools
            )
        )

        let script = scripts.isEmpty ? .events([.messageStop]) : scripts.removeFirst()
        switch script {
        case .events(let events):
            return AsyncThrowingStream { continuation in
                Task {
                    for event in events {
                        continuation.yield(event)
                    }
                    continuation.finish()
                }
            }
        case .error(let error):
            return AsyncThrowingStream { continuation in
                Task {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func completeToolUse(id: String, content: String, isError: Bool) async {
        completedToolUses.append(
            CompletedToolUse(
                id: id,
                content: content,
                isError: isError
            )
        )
    }

    func completedToolUseCount() -> Int {
        completedToolUses.count
    }

    func invocationsSnapshot() -> [Invocation] {
        invocations
    }

    func completedToolUsesSnapshot() -> [CompletedToolUse] {
        completedToolUses
    }
}

extension StubStreamingClient {
    enum Script {
        case events([StreamEvent])
        case error(Error)
    }

    struct Invocation {
        let messages: [Message]
        let contextBlock: String
        let tools: [Tool]
    }

    struct CompletedToolUse: Equatable {
        let id: String
        let content: String
        let isError: Bool
    }
}
