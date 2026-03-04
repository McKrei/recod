import Foundation

struct PostProcessedResult: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var actionID: UUID
    var actionName: String
    var providerID: String
    var modelID: String
    var messages: [LLMMessage]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        actionID: UUID,
        actionName: String,
        providerID: String,
        modelID: String,
        messages: [LLMMessage],
        createdAt: Date = .now
    ) {
        self.id = id
        self.actionID = actionID
        self.actionName = actionName
        self.providerID = providerID
        self.modelID = modelID
        self.messages = messages
        self.createdAt = createdAt
    }

    var outputText: String {
        messages.last(where: { $0.role == .assistant })?.content ?? ""
    }
}
