import Foundation

struct LLMMessage: Codable, Sendable, Identifiable, Hashable {
    enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }

    var id: UUID
    var role: Role
    var content: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}
