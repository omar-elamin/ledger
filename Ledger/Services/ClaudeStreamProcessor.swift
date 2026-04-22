import Foundation

struct ClaudeProcessedTurn {
    let emittedEvents: [StreamEvent]
    let streamedTurn: StreamedTurn
}

struct ClaudeStreamProcessor {
    private var parser = SSEAccumulator()
    private var turnState = TurnState()

    mutating func ingest(line rawLine: String) throws -> [StreamEvent] {
        let line = rawLine.trimmingCharacters(in: .newlines)
        var emittedEvents: [StreamEvent] = []

        if line.isEmpty {
            if let event = parser.consume() {
                try handleSSEEvent(event, emittedEvents: &emittedEvents)
            }
            return emittedEvents
        }

        if line.hasPrefix("event:"), let event = parser.consume() {
            try handleSSEEvent(event, emittedEvents: &emittedEvents)
        }

        parser.append(line: line)
        return emittedEvents
    }

    mutating func finish() throws -> ClaudeProcessedTurn {
        var emittedEvents: [StreamEvent] = []
        if let event = parser.consume() {
            try handleSSEEvent(event, emittedEvents: &emittedEvents)
        }

        return ClaudeProcessedTurn(
            emittedEvents: emittedEvents,
            streamedTurn: try turnState.finalizedTurn()
        )
    }

    private mutating func handleSSEEvent(
        _ event: SSEEvent,
        emittedEvents: inout [StreamEvent]
    ) throws {
        if event.data == "[DONE]" || event.name == "ping" {
            return
        }

        switch event.name {
        case "content_block_start":
            let payload = try JSONDecoder().decode(ContentBlockStartEvent.self, from: Data(event.data.utf8))
            switch payload.contentBlock {
            case .text:
                turnState.inProgressBlocks[payload.index] = .text("")
            case .toolUse(let toolUse):
                turnState.inProgressBlocks[payload.index] = .toolUse(
                    id: toolUse.id,
                    name: toolUse.name,
                    partialJSON: "",
                    initialInput: toolUse.input
                )
                turnState.toolUses.append(ToolUseIdentity(id: toolUse.id, name: toolUse.name))
                emittedEvents.append(.toolUseStart(id: toolUse.id, name: toolUse.name))
            }
        case "content_block_delta":
            let payload = try JSONDecoder().decode(ContentBlockDeltaEvent.self, from: Data(event.data.utf8))
            switch payload.delta {
            case .text(let text):
                if case .text(let currentText) = turnState.inProgressBlocks[payload.index] {
                    turnState.inProgressBlocks[payload.index] = .text(currentText + text)
                }
                emittedEvents.append(.textDelta(text))
            case .inputJSON(let partialJSON):
                guard case .toolUse(let id, let name, let currentJSON, let initialInput) = turnState.inProgressBlocks[payload.index] else {
                    return
                }
                turnState.inProgressBlocks[payload.index] = .toolUse(
                    id: id,
                    name: name,
                    partialJSON: currentJSON + partialJSON,
                    initialInput: initialInput
                )
                emittedEvents.append(.toolUseDelta(id: id, partialJSON: partialJSON))
            case .ignored:
                break
            }
        case "content_block_stop":
            let payload = try JSONDecoder().decode(ContentBlockStopEvent.self, from: Data(event.data.utf8))
            guard let block = turnState.inProgressBlocks.removeValue(forKey: payload.index) else {
                return
            }

            switch block {
            case .text(let text):
                turnState.finalizedBlocks[payload.index] = .text(text)
            case .toolUse(let id, let name, let partialJSON, let initialInput):
                let input = try ClaudeClient.toolInputJSONValue(
                    partialJSON: partialJSON,
                    initialInput: initialInput,
                    toolName: name
                )
                turnState.finalizedBlocks[payload.index] = .toolUse(id: id, name: name, input: input)
                emittedEvents.append(.toolUseEnd(id: id))
            }
        case "message_delta":
            let payload = try JSONDecoder().decode(MessageDeltaEvent.self, from: Data(event.data.utf8))
            if let stopReason = payload.delta.stopReason {
                turnState.stopReason = stopReason
            }
        case "message_stop", "message_start":
            break
        case "error":
            let payload = try JSONDecoder().decode(StreamErrorEvent.self, from: Data(event.data.utf8))
            throw ClaudeClientError.apiError(payload.error.message)
        default:
            break
        }
    }
}
