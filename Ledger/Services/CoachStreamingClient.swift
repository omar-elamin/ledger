import Foundation

protocol CoachStreamingClient {
    var hasAPIKeyConfigured: Bool { get }

    func streamMessage(
        messages: [Message],
        profile: String,
        todayLog: DayLog?,
        tools: [Tool]
    ) async -> AsyncThrowingStream<StreamEvent, Error>

    func completeToolUse(id: String, content: String, isError: Bool) async
}
