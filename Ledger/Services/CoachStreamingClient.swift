import Foundation

protocol CoachStreamingClient {
    var hasAPIKeyConfigured: Bool { get }

    func streamMessage(
        messages: [Message],
        contextBlock: String,
        tools: [Tool]
    ) async -> AsyncThrowingStream<StreamEvent, Error>

    func completeToolUse(id: String, content: String, isError: Bool) async
}
