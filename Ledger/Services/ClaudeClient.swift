import Foundation

enum StreamEvent: Sendable, Equatable {
    case textDelta(String)
    case toolUseStart(id: String, name: String)
    case toolUseDelta(id: String, partialJSON: String)
    case toolUseEnd(id: String)
    case messageStop
}

enum JSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case object([String: JSONValue])
    case array([JSONValue])
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    static func from(data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

struct ToolExecutionResult: Sendable {
    let content: String
    let isError: Bool
}

protocol MemoryTextGeneratingClient: Sendable {
    var hasAPIKeyConfigured: Bool { get }

    func generateText(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> String
}

enum ClaudeClientError: LocalizedError {
    case invalidResponse
    case apiError(String)
    case toolResultMissing(String)
    case malformedToolInput(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Anthropic returned an invalid response."
        case .apiError(let message):
            return message
        case .toolResultMissing(let id):
            return "No tool result was provided for tool use \(id)."
        case .malformedToolInput(let name):
            return "Tool input for \(name) was not valid JSON."
        }
    }
}

actor ClaudeClient: CoachStreamingClient, MemoryTextGeneratingClient {
    static let model = "claude-opus-4-7"

    private let session: URLSession
    private var waitingToolResults: [String: CheckedContinuation<ToolExecutionResult, Never>] = [:]
    private var completedToolResults: [String: ToolExecutionResult] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated var hasAPIKeyConfigured: Bool {
        !Secrets.anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func streamMessage(
        messages: [Message],
        contextBlock: String,
        tools: [Tool]
    ) async -> AsyncThrowingStream<StreamEvent, Error> {
        let systemPrompt = CoachPrompt.systemPrompt(contextBlock: contextBlock)
        let initialMessages = messages.map { APIMessage(message: $0) }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.runConversationLoop(
                        messages: initialMessages,
                        systemPrompt: systemPrompt,
                        tools: tools,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func generateText(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 1024
    ) async throws -> String {
        let requestBody = MessagesRequest(
            model: Self.model,
            system: systemPrompt,
            maxTokens: maxTokens,
            stream: false,
            messages: [
                APIMessage(
                    role: "user",
                    content: [.text(userPrompt)]
                )
            ],
            tools: []
        )

        let request = try makeRequest(for: requestBody)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeClientError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown API error."
            throw ClaudeClientError.apiError(Self.extractAPIError(from: body))
        }

        let message = try JSONDecoder().decode(ClaudeMessageResponse.self, from: data)
        let text = message.content
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw ClaudeClientError.invalidResponse
        }

        return text
    }

    func completeToolUse(id: String, content: String, isError: Bool = false) async {
        let result = ToolExecutionResult(content: content, isError: isError)
        if let continuation = waitingToolResults.removeValue(forKey: id) {
            continuation.resume(returning: result)
        } else {
            completedToolResults[id] = result
        }
    }

    private func runConversationLoop(
        messages: [APIMessage],
        systemPrompt: String,
        tools: [Tool],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var conversation = messages

        while true {
            let streamedTurn = try await streamTurn(
                messages: conversation,
                systemPrompt: systemPrompt,
                tools: tools,
                continuation: continuation
            )

            conversation.append(
                APIMessage(role: "assistant", content: streamedTurn.assistantBlocks)
            )

            if streamedTurn.stopReason == "tool_use" {
                let toolResults = await streamedTurn.toolUses.asyncMap { toolUse in
                    let result = await self.awaitToolResult(id: toolUse.id)
                    return APIMessageContent.toolResult(
                        id: toolUse.id,
                        content: result.content,
                        isError: result.isError
                    )
                }
                conversation.append(APIMessage(role: "user", content: toolResults))
                continue
            }

            continuation.yield(.messageStop)
            return
        }
    }

    private func awaitToolResult(id: String) async -> ToolExecutionResult {
        if let completed = completedToolResults.removeValue(forKey: id) {
            return completed
        }

        return await withCheckedContinuation { continuation in
            waitingToolResults[id] = continuation
        }
    }

    private func streamTurn(
        messages: [APIMessage],
        systemPrompt: String,
        tools: [Tool],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws -> StreamedTurn {
        let requestBody = MessagesRequest(
            model: Self.model,
            system: systemPrompt,
            maxTokens: 2048,
            stream: true,
            messages: messages,
            tools: tools
        )

        let request = try makeRequest(for: requestBody)

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeClientError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let body = try await readBody(from: bytes)
            throw ClaudeClientError.apiError(Self.extractAPIError(from: body))
        }

        var processor = ClaudeStreamProcessor()

        for try await rawLine in bytes.lines {
            for event in try processor.ingest(line: rawLine) {
                continuation.yield(event)
            }
        }

        let processedTurn = try processor.finish()
        for event in processedTurn.emittedEvents {
            continuation.yield(event)
        }
        return processedTurn.streamedTurn
    }

    static func toolInputJSONValue(
        partialJSON: String,
        initialInput: JSONValue?,
        toolName: String
    ) throws -> JSONValue {
        if !partialJSON.isEmpty {
            guard let data = partialJSON.data(using: .utf8) else {
                throw ClaudeClientError.malformedToolInput(toolName)
            }
            return try JSONValue.from(data: data)
        }

        if let initialInput {
            return initialInput
        }

        return .object([:])
    }

    private func readBody(from bytes: URLSession.AsyncBytes) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return String(data: data, encoding: .utf8) ?? "Unknown API error."
    }

    private static func extractAPIError(from body: String) -> String {
        guard
            let data = body.data(using: .utf8),
            let payload = try? JSONDecoder().decode(TopLevelAPIError.self, from: data)
        else {
            return body
        }

        return payload.error.message
    }

    private func makeRequest(for requestBody: MessagesRequest) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(Secrets.anthropicAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        return request
    }
}

struct MessagesRequest: Encodable {
    let model: String
    let system: String
    let maxTokens: Int
    let stream: Bool
    let messages: [APIMessage]
    let tools: [Tool]

    enum CodingKeys: String, CodingKey {
        case model
        case system
        case maxTokens = "max_tokens"
        case stream
        case messages
        case tools
    }
}

struct APIMessage: Encodable {
    let role: String
    let content: [APIMessageContent]

    init(role: String, content: [APIMessageContent]) {
        self.role = role
        self.content = content
    }

    init(message: Message) {
        self.role = message.role == .user ? "user" : "assistant"
        self.content = [.text(message.content)]
    }

    init(_ message: Message) {
        self.init(message: message)
    }
}

enum APIMessageContent: Encodable {
    case text(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(id: String, content: String, isError: Bool)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case id
        case name
        case input
        case toolUseID = "tool_use_id"
        case content
        case isError = "is_error"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let id, let content, let isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(id, forKey: .toolUseID)
            try container.encode(content, forKey: .content)
            if isError {
                try container.encode(true, forKey: .isError)
            }
        }
    }
}

struct StreamedTurn {
    let assistantBlocks: [APIMessageContent]
    let toolUses: [ToolUseIdentity]
    let stopReason: String
}

struct ToolUseIdentity {
    let id: String
    let name: String
}

struct TurnState {
    var inProgressBlocks: [Int: InProgressBlock] = [:]
    var finalizedBlocks: [Int: APIMessageContent] = [:]
    var toolUses: [ToolUseIdentity] = []
    var stopReason: String = "end_turn"

    func finalizedTurn() throws -> StreamedTurn {
        let orderedBlocks = finalizedBlocks
            .sorted { $0.key < $1.key }
            .map(\.value)
        return StreamedTurn(
            assistantBlocks: orderedBlocks,
            toolUses: toolUses,
            stopReason: stopReason
        )
    }
}

enum InProgressBlock {
    case text(String)
    case toolUse(id: String, name: String, partialJSON: String, initialInput: JSONValue?)
}

struct SSEAccumulator {
    private var eventName: String?
    private var dataLines: [String] = []

    mutating func append(line: String) {
        if line.hasPrefix("event:") {
            eventName = Self.value(from: line)
        } else if line.hasPrefix("data:") {
            dataLines.append(Self.value(from: line))
        }
    }

    mutating func consume() -> SSEEvent? {
        guard let eventName else {
            dataLines.removeAll()
            return nil
        }

        defer {
            self.eventName = nil
            dataLines.removeAll()
        }

        return SSEEvent(name: eventName, data: dataLines.joined(separator: "\n"))
    }

    private static func value(from line: String) -> String {
        String(line.drop { $0 != ":" }.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
}

struct SSEEvent {
    let name: String
    let data: String
}

struct ContentBlockStartEvent: Decodable {
    let index: Int
    let contentBlock: ContentBlock

    enum CodingKeys: String, CodingKey {
        case index
        case contentBlock = "content_block"
    }
}

enum ContentBlock: Decodable {
    case text
    case toolUse(ToolUseStartPayload)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case name
        case input
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "text":
            self = .text
        case "tool_use":
            self = .toolUse(
                ToolUseStartPayload(
                    id: try container.decode(String.self, forKey: .id),
                    name: try container.decode(String.self, forKey: .name),
                    input: try container.decodeIfPresent(JSONValue.self, forKey: .input)
                )
            )
        default:
            self = .text
        }
    }
}

struct ToolUseStartPayload: Decodable {
    let id: String
    let name: String
    let input: JSONValue?
}

struct ContentBlockDeltaEvent: Decodable {
    let index: Int
    let delta: ContentBlockDelta
}

enum ContentBlockDelta: Decodable {
    case text(String)
    case inputJSON(String)
    case ignored

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case partialJSON = "partial_json"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "text_delta":
            self = .text(try container.decode(String.self, forKey: .text))
        case "input_json_delta":
            self = .inputJSON(try container.decode(String.self, forKey: .partialJSON))
        default:
            self = .ignored
        }
    }
}

struct ContentBlockStopEvent: Decodable {
    let index: Int
}

struct MessageDeltaEvent: Decodable {
    let delta: MessageDeltaPayload
}

struct MessageDeltaPayload: Decodable {
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case stopReason = "stop_reason"
    }
}

struct StreamErrorEvent: Decodable {
    let error: APIErrorPayload
}

struct TopLevelAPIError: Decodable {
    let error: APIErrorPayload
}

struct APIErrorPayload: Decodable {
    let type: String
    let message: String
}

struct ClaudeMessageResponse: Decodable {
    let content: [ClaudeMessageContent]
}

struct ClaudeMessageContent: Decodable {
    let type: String
    let text: String?
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var results: [T] = []
        results.reserveCapacity(count)
        for element in self {
            let transformed = try await transform(element)
            results.append(transformed)
        }
        return results
    }
}
