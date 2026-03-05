import Foundation

@MainActor
final class FileOutputService {
    static let shared = FileOutputService()

    private init() {}

    // MARK: - Public API

    @discardableResult
    func saveText(_ text: String, for action: PostProcessingAction, date: Date = .now) async -> Bool {
        guard action.saveToFileEnabled else { return false }

        guard let rawPath = action.saveToFilePath,
              !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await FileLogger.shared.log(
                "File output skipped: no configured path for action=\(action.name)",
                level: .warning
            )
            return false
        }

        do {
            let fileURL: URL
            switch action.fileSaveMode {
            case .newFile:
                try validateDirectoryPath(rawPath)
                let directoryURL = URL(fileURLWithPath: rawPath, isDirectory: true)
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )

                let template = resolvedTemplate(action.saveToFileTemplate)
                let fileName = expandTemplate(template, date: date) + action.effectiveExtension
                fileURL = directoryURL.appendingPathComponent(fileName)

            case .existingFile:
                try validateAppendFilePath(rawPath)
                fileURL = URL(fileURLWithPath: rawPath)
            }

            try appendText(text, to: fileURL, separator: action.effectiveSeparator)

            await FileLogger.shared.log(
                "File output success: action=\(action.name), file=\(fileURL.path), chars=\(text.count)",
                level: .info
            )
            return true
        } catch {
            await FileLogger.shared.log(
                "File output failed: action=\(action.name), error=\(error.localizedDescription)",
                level: .error
            )
            return false
        }
    }

    func expandTemplate(_ template: String, date: Date) -> String {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )

        var result = template
        result = result.replacingOccurrences(of: "{YYYY}", with: String(format: "%04d", components.year ?? 0))
        result = result.replacingOccurrences(of: "{YY}", with: String(format: "%02d", (components.year ?? 0) % 100))
        result = result.replacingOccurrences(of: "{MM}", with: String(format: "%02d", components.month ?? 0))
        result = result.replacingOccurrences(of: "{DD}", with: String(format: "%02d", components.day ?? 0))
        result = result.replacingOccurrences(of: "{HH}", with: String(format: "%02d", components.hour ?? 0))
        result = result.replacingOccurrences(of: "{mm}", with: String(format: "%02d", components.minute ?? 0))
        result = result.replacingOccurrences(of: "{ss}", with: String(format: "%02d", components.second ?? 0))
        return result
    }

    func previewFilename(template: String, extension ext: String, date: Date = .now) -> String {
        let safeTemplate = resolvedTemplate(template)
        let safeExtension = ext.hasPrefix(".") ? ext : ".\(ext)"
        return expandTemplate(safeTemplate, date: date) + safeExtension
    }

    // MARK: - File I/O

    private func appendText(_ text: String, to fileURL: URL, separator: String) throws {
        guard let textData = text.data(using: .utf8) else {
            throw FileOutputError.encodingFailed
        }

        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        guard fileExists else {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            return
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { handle.closeFile() }
        handle.seekToEndOfFile()

        if handle.offsetInFile > 0 {
            guard let separatorData = separator.data(using: .utf8) else {
                throw FileOutputError.encodingFailed
            }
            handle.write(separatorData)
        }

        handle.write(textData)
    }

    private func resolvedTemplate(_ rawTemplate: String?) -> String {
        guard let rawTemplate else {
            return PostProcessingAction.defaultSaveToFileTemplate
        }

        let trimmed = rawTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? PostProcessingAction.defaultSaveToFileTemplate : trimmed
    }

    private func validateDirectoryPath(_ path: String) throws {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        if exists && !isDirectory.boolValue {
            throw FileOutputError.pathIsNotDirectory(path)
        }
    }

    private func validateAppendFilePath(_ path: String) throws {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        if exists && isDirectory.boolValue {
            throw FileOutputError.pathIsDirectory(path)
        }
    }
}

extension FileOutputService {
    enum FileOutputError: LocalizedError {
        case encodingFailed
        case pathIsNotDirectory(String)
        case pathIsDirectory(String)

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode text as UTF-8"
            case .pathIsNotDirectory(let path):
                return "Configured new-file path is not a directory: \(path)"
            case .pathIsDirectory(let path):
                return "Configured append path points to a directory: \(path)"
            }
        }
    }
}
