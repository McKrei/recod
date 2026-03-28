import AppKit
import Foundation
import UniformTypeIdentifiers

enum FilePanelService {
    @MainActor
    static func chooseDirectory(prompt: String = "Select Directory") -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = prompt

        return runOpenPanel(panel)?.path
    }

    @MainActor
    static func chooseTextFile(prompt: String = "Select File") -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .text]
        panel.prompt = prompt

        return runOpenPanel(panel)?.path
    }

    @MainActor
    static func chooseJSONSaveURL(
        suggestedFileName: String,
        title: String,
        prompt: String
    ) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = suggestedFileName
        panel.title = title
        panel.prompt = prompt

        return runSavePanel(panel)
    }

    @MainActor
    static func chooseJSONOpenURL(title: String, prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = title
        panel.prompt = prompt

        return runOpenPanel(panel)
    }

    static func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    @MainActor
    private static func runOpenPanel(_ panel: NSOpenPanel) -> URL? {
        activateForPanelPresentation()
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    private static func runSavePanel(_ panel: NSSavePanel) -> URL? {
        activateForPanelPresentation()
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    private static func activateForPanelPresentation() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
