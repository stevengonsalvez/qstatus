import AppKit
import SwiftUI
import Core

@main
struct QStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { PreferencesWindow() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Make this a proper menu bar app (no Dock icon)
        NSApp.setActivationPolicy(.accessory)
        let settings = SettingsStore()
        let metrics = MetricsCalculator()
        let reader = QDBReader(defaultContextWindow: settings.defaultContextWindowTokens)
        let coordinator = UpdateCoordinator(reader: reader, metrics: metrics, settings: settings)

        let controller = MenuBarController(coordinator: coordinator, settings: settings)
        controller.setupStatusItem()
        controller.startPolling()
        self.menuBarController = controller

        if settings.notificationsEnabled {
            Task { await Notifier.requestAuthorization() }
        }
        // Expose settings and refresh to the view model for UI toggles/buttons
        coordinator.viewModel.settings = settings
        coordinator.viewModel.forceRefresh = { [weak coordinator] in
            coordinator?.manualRefresh()
        }
    }
}
