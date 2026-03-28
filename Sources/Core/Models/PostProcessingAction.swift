import Foundation
import SwiftData

@Model
final class PostProcessingAction {
    @Attribute(.unique) var id: UUID
    var name: String
    var prompt: String
    var systemPrompt: String?
    var providerID: String
    var modelID: String
    var isAutoEnabled: Bool
    var hotkey: HotKeyShortcut?
    var sortOrder: Int
    var createdAt: Date

    // MARK: - Save to File

    @Attribute(originalName: "saveToFileEnabled") var saveToFileEnabledRaw: Bool?
    var saveToFileMode: String?
    var saveToFilePath: String?
    var saveToFileTemplate: String?
    var saveToFileSeparator: String?
    var saveToFileExtension: String?

    init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        systemPrompt: String? = nil,
        providerID: String,
        modelID: String,
        isAutoEnabled: Bool = false,
        hotkey: HotKeyShortcut? = nil,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        saveToFileEnabled: Bool = false,
        saveToFileMode: String? = nil,
        saveToFilePath: String? = nil,
        saveToFileTemplate: String? = nil,
        saveToFileSeparator: String? = nil,
        saveToFileExtension: String? = nil
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.providerID = providerID
        self.modelID = modelID
        self.isAutoEnabled = isAutoEnabled
        self.hotkey = hotkey
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.saveToFileEnabledRaw = saveToFileEnabled
        self.saveToFileMode = saveToFileMode
        self.saveToFilePath = saveToFilePath
        self.saveToFileTemplate = saveToFileTemplate
        self.saveToFileSeparator = saveToFileSeparator
        self.saveToFileExtension = saveToFileExtension
    }
}

extension PostProcessingAction {
    static let defaultSaveToFileTemplate = "recod-{YYYY}-{MM}-{DD}_{HH}{mm}{ss}"
    static let defaultSaveToFileSeparator = "\\n---\\n"
    static let defaultSaveToFileExtension = ".txt"

    var saveToFileEnabled: Bool {
        get { saveToFileEnabledRaw ?? false }
        set { saveToFileEnabledRaw = newValue }
    }

    var trimmedSystemPrompt: String? {
        systemPrompt.nilIfBlank
    }

    var hasCustomSystemPrompt: Bool {
        trimmedSystemPrompt != nil
    }

    var fileSaveMode: SaveToFileMode {
        get { SaveToFileMode(rawValue: saveToFileMode ?? "") ?? .newFile }
        set { saveToFileMode = newValue.rawValue }
    }

    var effectiveSeparator: String {
        let raw = saveToFileSeparator ?? Self.defaultSaveToFileSeparator
        return raw
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
    }

    var effectiveExtension: String {
        let ext = saveToFileExtension.nilIfBlank ?? Self.defaultSaveToFileExtension
        return ext.hasPrefix(".") ? ext : ".\(ext)"
    }
}
