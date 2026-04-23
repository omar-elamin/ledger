import Foundation

enum MessageRole: String, Sendable {
    case user
    case coach
}

struct Message: Identifiable, Equatable, Sendable {
    var id: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}
