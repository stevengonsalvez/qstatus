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
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Make this a proper menu bar app (no Dock icon)
        NSApp.setActivationPolicy(.accessory)
        let settings = SettingsStore()
        let metrics = MetricsCalculator()

        // Create initial data source based on settings
        let dataSource = DataSourceFactory.create(type: settings.dataSourceType, settings: settings)
        let coordinator = UpdateCoordinator(reader: dataSource, metrics: metrics, settings: settings)

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

        // Handle data source switching
        coordinator.viewModel.onSwitchProvider = { [weak coordinator, weak settings] newProvider in
            guard let coordinator = coordinator,
                  let settings = settings else { return }

            // Update settings
            settings.dataSourceType = newProvider
            settings.saveToDisk()

            // Create new data source
            let newReader = DataSourceFactory.create(type: newProvider, settings: settings)

            // Restart coordinator with new data source
            await coordinator.restart(with: newReader)
        }

        // Setup global keyboard shortcuts
        setupKeyboardShortcuts(coordinator: coordinator)
    }

    private func setupKeyboardShortcuts(coordinator: UpdateCoordinator) {
        // Monitor for Cmd+Shift+Q globally
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Check for Cmd+Shift+Q
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 12 { // Q key
                // Open dashboard
                DispatchQueue.main.async {
                    coordinator.viewModel.showAllSheet = true
                    // Dashboard will open as a sheet
                }
            }
        }

        // Also add local monitoring for when app is active
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 12 { // Q key
                DispatchQueue.main.async {
                    coordinator.viewModel.showAllSheet = true
                }
                return nil // Consume the event
            }
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}