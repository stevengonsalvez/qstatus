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

        // Calculate critical percentage the same way as dropdown view
        let criticalPct = calculateCriticalPercentage(vm: vm)

        switch settings.iconMode {
        case .mostRecent:
            if let s = mostRecentSession(from: vm.sessions) {
                percent = Int(criticalPct.rounded())
                state = criticalPct >= 95 ? .critical : (criticalPct >= 80 ? .warning : (criticalPct <= 0 ? .idle : .healthy))
                tooltip = "\(cwdTail(s.cwd ?? s.id)) • \(percent)% • \(CostEstimator.formatUSD(s.costUSD)) • \(s.messageCount) msgs"
            } else {
                percent = Int(criticalPct.rounded())
                state = vm.health
                tooltip = "Most‑Recent: \(percent)%"
            }
        case .frontmostTerminal:
            if let path = FrontmostTerminalResolver.resolveCWD(),
               let s = pinnedSession(from: vm.sessions, key: path) {
                percent = Int(criticalPct.rounded())
                state = criticalPct >= 95 ? .critical : (criticalPct >= 80 ? .warning : (criticalPct <= 0 ? .idle : .healthy))
                tooltip = "Frontmost • \(cwdTail(s.cwd ?? s.id)) • \(percent)%"
            } else if let s = mostRecentSession(from: vm.sessions) {
                percent = Int(criticalPct.rounded())
                state = criticalPct >= 95 ? .critical : (criticalPct >= 80 ? .warning : (criticalPct <= 0 ? .idle : .healthy))
                tooltip = "Frontmost (fallback) • \(cwdTail(s.cwd ?? s.id)) • \(percent)%"
            } else {
                percent = Int(criticalPct.rounded())
                state = vm.health
                tooltip = "Frontmost (fallback) • \(percent)%"
            }
        case .pinned:
            if let key = settings.pinnedSessionKey, let s = pinnedSession(from: vm.sessions, key: key) {
                percent = Int(criticalPct.rounded())
                state = criticalPct >= 95 ? .critical : (criticalPct >= 80 ? .warning : (criticalPct <= 0 ? .idle : .healthy))
                tooltip = "Pinned • \(cwdTail(s.cwd ?? s.id)) • \(percent)%"
            } else {
                percent = 0; state = .idle
                tooltip = "Pinned: not found"
            }
        case .monthlyMessages:
            // For Claude Code, show cost against plan; for Amazon Q show messages
            if settings.dataSourceType == .claudeCode {
                let plan = settings.claudePlan
                if plan != .free {
                    // Use the same critical percentage calculation from the top
                    percent = Int(criticalPct.rounded())
                    state = (criticalPct >= 95 ? .critical : (criticalPct >= 80 ? .warning : (criticalPct <= 0 ? .idle : .healthy)))
                    labelOverride = "\(percent)%"

                    // Build appropriate tooltip based on what we have
                    if let activeSession = vm.activeClaudeSession,
                       let block = activeSession.currentBlock {
                        // Active block - show which metric is critical
                        let costBaseline = 140.0
                        let costPct = min(100.0, (block.costUSD / costBaseline) * 100.0)
                        let tokenBaseline = Double(vm.maxTokensFromPreviousBlocks ?? 10_000_000)
                        let tokenPct = tokenBaseline > 0 ? min(100.0, (Double(block.tokenCounts.totalTokens) / tokenBaseline) * 100.0) : 0

                        if tokenPct >= costPct {
                            let tokenDisplay = formatTokenCount(block.tokenCounts.totalTokens)
                            let limitDisplay = formatTokenCount(Int(tokenBaseline))
                            tooltip = "Claude Block \(activeSession.blockNumber): \(tokenDisplay)/\(limitDisplay) tokens (\(percent)%)"
                        } else {
                            let costDisplay = CostEstimator.formatUSD(block.costUSD)
                            tooltip = "Claude Block \(activeSession.blockNumber): \(costDisplay)/$140.00 (\(percent)%)"
                        }
                    } else {
                        // No active block - show monthly usage
                        let costDisplay = CostEstimator.formatUSD(vm.costMonth)
                        let limitDisplay = CostEstimator.formatUSD(plan.costLimit)
                        tooltip = "Claude \(plan.displayName): \(costDisplay)/\(limitDisplay) (\(percent)%)"
                    }
                } else {
                    // Free plan
                    percent = 0
                    state = .idle
                    labelOverride = "Free"
                    tooltip = "Claude Free Plan - No tracking"
                }
            } else {
                // Original message-based display for Amazon Q or free plan
                let pct = min(100.0, (Double(vm.messagesMonth)/5000.0)*100.0)
                percent = Int(pct.rounded())
                state = (pct >= 90 ? .critical : (pct >= 70 ? .warning : (pct <= 0 ? .idle : .healthy)))
                labelOverride = "\(Int(round(pct)))%"
                tooltip = "Monthly messages: \(vm.messagesMonth)/5000"
            }
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
    private func formatTokenCount(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1000 {
            return String(format: "%.1fK", Double(tokens) / 1_000)
        } else {
            return "\(tokens)"
        }
    }

    /// Calculate critical percentage the same way as dropdown view
    private func calculateCriticalPercentage(vm: UsageViewModel) -> Double {
        // Check if we have an active Claude session with a block
        if let activeSession = vm.activeClaudeSession,
           let block = activeSession.currentBlock {
            // Active block - calculate both token and cost percentages, use the higher one
            let costBaseline = 140.0
            let costPct = min(100.0, (block.costUSD / costBaseline) * 100.0)

            // Token percentage - use personal max or 10M baseline
            let tokenBaseline = Double(vm.maxTokensFromPreviousBlocks ?? 10_000_000)
            let tokenPct = tokenBaseline > 0 ? min(100.0, (Double(block.tokenCounts.totalTokens) / tokenBaseline) * 100.0) : 0

            // Use the higher percentage (critical limit)
            return max(tokenPct, costPct)
        } else if let activeSession = vm.activeClaudeSession {
            // Have active session but no block - use session data
            // This matches what the dropdown shows for currentTokens and currentCost
            let costBaseline = 140.0
            let costPct = min(100.0, (activeSession.cost / costBaseline) * 100.0)

            let tokenBaseline = Double(vm.maxTokensFromPreviousBlocks ?? 10_000_000)
            let tokenPct = tokenBaseline > 0 ? min(100.0, (Double(activeSession.tokens) / tokenBaseline) * 100.0) : 0

            return max(tokenPct, costPct)
        } else {
            // No active session - use monthly data
            let plan = settings.claudePlan
            if plan != .free && plan.costLimit > 0 {
                return min(100.0, (vm.costMonth / plan.costLimit) * 100.0)
            }
            return 0
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown { closePopover(sender) } else { showPopover(sender) }
    }

    private func showPopover(_ sender: Any?) {
        if hostingController == nil {
            let vm = coordinator.viewModel
            // Set up provider switch callback
            vm.onSwitchProvider = { [weak self] provider in
                await self?.switchProvider(to: provider)
            }
            let view = DropdownView(viewModel: vm)
            let controller = NSHostingController(rootView: view)
            hostingController = controller
            popover.contentViewController = controller
            popover.contentSize = NSSize(width: 500, height: 400)
        }
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func closePopover(_ sender: Any?) {
        popover.performClose(sender)
    }

    func switchProvider(to provider: DataSourceType) async {
        // Create new data source
        let newDataSource = DataSourceFactory.create(type: provider, settings: settings)

        // Update settings
        settings.dataSourceType = provider
        settings.saveToDisk()

        // Restart coordinator with new data source
        await coordinator.restart(with: newDataSource)
    }
}
