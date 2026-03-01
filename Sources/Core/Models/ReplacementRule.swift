import Foundation
import SwiftData

@Model
final class ReplacementRule {
    @Attribute(.unique) var id: UUID
    var textToReplace: String
    var additionalIncorrectForms: [String] = []
    var replacementText: String
    var createdAt: Date
    var weight: Float = 1.5
    var useFuzzyMatching: Bool = true

    init(
        id: UUID = UUID(),
        textToReplace: String,
        additionalIncorrectForms: [String] = [],
        replacementText: String,
        createdAt: Date = .now,
        weight: Float = 1.5,
        useFuzzyMatching: Bool = true
    ) {
        self.id = id
        self.textToReplace = textToReplace
        self.additionalIncorrectForms = additionalIncorrectForms
        self.replacementText = replacementText
        self.createdAt = createdAt
        self.weight = weight
        self.useFuzzyMatching = useFuzzyMatching
    }
}
