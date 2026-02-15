import Foundation
import SwiftData

@Model
final class ReplacementRule {
    @Attribute(.unique) var id: UUID
    var textToReplace: String
    var replacementText: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        textToReplace: String,
        replacementText: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.textToReplace = textToReplace
        self.replacementText = replacementText
        self.createdAt = createdAt
    }
}
