import Sparkle
import SwiftUI

/// Обёртка над Sparkle для интеграции с SwiftUI.
/// Управляет проверкой обновлений через SPUStandardUpdaterController.
/// Sparkle инициализируется только при запуске из .app бандла.
@MainActor
final class UpdaterManager: ObservableObject {
    private var updaterController: SPUStandardUpdaterController?

    @Published var canCheckForUpdates = false

    /// Проверяет, запущено ли приложение из .app бандла
    private var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    init() {
        guard isRunningFromAppBundle else {
            print("[UpdaterManager] Not running from .app bundle — Sparkle disabled")
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterController = controller

        // Наблюдаем за состоянием updater
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}
