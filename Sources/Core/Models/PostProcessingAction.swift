import Foundation
import SwiftData

@Model
final class PostProcessingAction {
    @Attribute(.unique) var id: UUID
    var name: String
    var prompt: String
    var providerID: String
    var modelID: String
    var isAutoEnabled: Bool
    var hotkey: HotKeyShortcut?
    var sortOrder: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        providerID: String,
        modelID: String,
        isAutoEnabled: Bool = false,
        hotkey: HotKeyShortcut? = nil,
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.providerID = providerID
        self.modelID = modelID
        self.isAutoEnabled = isAutoEnabled
        self.hotkey = hotkey
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
