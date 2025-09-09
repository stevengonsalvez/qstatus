import AppKit
import SwiftUI
import Core

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let coordinator: UpdateCoordinator
    private let settings: SettingsStore

    private var hostingController: NSViewController?

    init(coordinator: UpdateCoordinator, settings: SettingsStore) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.coordinator = coordinator
        self.settings = settings
        super.init()
        self.popover.behavior = .transient
        self.coordinator.onUIUpdate = { [weak self] vm in
            Task { await self?.updateIcon(state: vm.health, percent: vm.percent) }
        }
    }

    func setupStatusItem() {
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            updateIcon(state: .idle, percent: 0)
        }
    }

    func startPolling() {
        coordinator.start()
    }

    func updateIcon(state: HealthState, percent: Int) {
        guard let button = statusItem.button else { return }
        let image = IconBadgeRenderer.render(percentage: percent, state: state)
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "Q-Status: \(percent)% used"
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown { closePopover(sender) } else { showPopover(sender) }
    }

    private func showPopover(_ sender: Any?) {
        if hostingController == nil {
            let vm = coordinator.viewModel
            let view = DropdownView(viewModel: vm)
            let controller = NSHostingController(rootView: view)
            hostingController = controller
            popover.contentViewController = controller
            popover.contentSize = NSSize(width: 320, height: 360)
        }
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func closePopover(_ sender: Any?) {
        popover.performClose(sender)
    }
}

