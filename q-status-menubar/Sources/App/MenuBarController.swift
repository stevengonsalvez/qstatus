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
            self?.updateIcon(using: vm)
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

    func updateIcon(state: HealthState, percent: Int) { // legacy
        guard let button = statusItem.button else { return }
        let image = IconBadgeRenderer.render(percentage: percent, state: state)
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "Q-Status: \(percent)% used"
    }

    func updateIcon(using vm: UsageViewModel) {
        guard let button = statusItem.button else { return }
        var percent = 0
        var state: HealthState = .idle
        var labelOverride: String? = nil
        var tooltip = "Q-Status"

        switch settings.iconMode {
        case .mostRecent:
            if let s = mostRecentSession(from: vm.sessions) {
                percent = Int(s.usagePercent.rounded())
                state = mapState(s.state)
                tooltip = "\(cwdTail(s.cwd ?? s.id)) • \(percent)% • \(CostEstimator.formatUSD(s.costUSD)) • \(s.messageCount) msgs"
            } else {
                percent = vm.percent
                state = vm.health
                tooltip = "Most‑Recent: \(percent)%"
            }
        case .frontmostTerminal:
            if let path = FrontmostTerminalResolver.resolveCWD(),
               let s = pinnedSession(from: vm.sessions, key: path) {
                percent = Int(s.usagePercent.rounded())
                state = mapState(s.state)
                tooltip = "Frontmost • \(cwdTail(s.cwd ?? s.id)) • \(percent)%"
            } else if let s = mostRecentSession(from: vm.sessions) {
                percent = Int(s.usagePercent.rounded())
                state = mapState(s.state)
                tooltip = "Frontmost (fallback) • \(cwdTail(s.cwd ?? s.id)) • \(percent)%"
            } else {
                percent = vm.percent
                state = vm.health
                tooltip = "Frontmost (fallback) • \(percent)%"
            }
        case .pinned:
            if let key = settings.pinnedSessionKey, let s = pinnedSession(from: vm.sessions, key: key) {
                percent = Int(s.usagePercent.rounded())
                state = mapState(s.state)
                tooltip = "Pinned • \(cwdTail(s.cwd ?? s.id)) • \(percent)%"
            } else {
                percent = 0; state = .idle
                tooltip = "Pinned: not found"
            }
        case .monthlyMessages:
            let pct = min(100.0, (Double(vm.messagesMonth)/5000.0)*100.0)
            percent = Int(pct.rounded())
            state = (pct >= 90 ? .critical : (pct >= 70 ? .warning : (pct <= 0 ? .idle : .healthy)))
            labelOverride = "\(Int(round(pct)))%"
            tooltip = "Monthly messages: \(vm.messagesMonth)/5000"
        }

        let activeCount = settings.showActiveBadge ? activeSessionsCount(from: vm.sessions) : 0
        let image = IconBadgeRenderer.render(percentage: percent, state: state, badge: activeCount, labelOverride: labelOverride)
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
    }

    private func mostRecentSession(from sessions: [SessionSummary]) -> SessionSummary? {
        sessions.sorted { ($0.internalRowID ?? 0) > ($1.internalRowID ?? 0) }.first
    }
    private func pinnedSession(from sessions: [SessionSummary], key: String) -> SessionSummary? {
        if let s = sessions.first(where: { $0.id == key }) { return s }
        if let s = sessions.first(where: { ($0.cwd ?? "") == key }) { return s }
        // fuzzy last path component
        if let s = sessions.first(where: { (($0.cwd as NSString?)?.lastPathComponent ?? "") == key }) { return s }
        return nil
    }
    private func activeSessionsCount(from sessions: [SessionSummary]) -> Int {
        let now = Date()
        let recent = sessions.filter { s in
            if let ts = s.lastActivity { return now.timeIntervalSince(ts) <= 120 } // 2 minutes
            return false
        }
        return recent.count
    }
    private func cwdTail(_ p: String) -> String { (p as NSString).lastPathComponent }
    private func mapState(_ s: SessionState) -> HealthState {
        switch s { case .critical: return .critical; case .warn: return .warning; default: return .healthy }
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
