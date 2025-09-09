import Foundation

public final class UpdateCoordinator: @unchecked Sendable {
    public let reader: QDBReader
    public let metrics: MetricsCalculator
    public let settings: SettingsStore

    public var onUIUpdate: ((UsageViewModel) -> Void)?
    public let viewModel: UsageViewModel

    private var timerTask: Task<Void, Never>?
    private var history: [UsageSnapshot] = []
    private var lastDataVersion: Int = -1
    private var stableCycles: Int = 0
    private var sessionsPage: Int = 0
    private let pageSize: Int = 50
    // Compaction heuristics
    private var lastSessionMetrics: [String: (tokens: Int, messages: Int, usage: Double)] = [:]
    private var compactingUntil: [String: Date] = [:]

    public init(reader: QDBReader, metrics: MetricsCalculator, settings: SettingsStore) {
        self.reader = reader
        self.metrics = metrics
        self.settings = settings
        self.viewModel = UsageViewModel()
        self.viewModel.onSelectSession = { [weak self] session in
            guard let self else { return }
            Task {
                if let details = try? await self.reader.fetchSessionDetail(key: session.id) {
                    await MainActor.run { self.viewModel.selectedSession = details }
                }
            }
        }
        self.viewModel.onOpenAll = { [weak self] in
            guard let self else { return }
            Task {
                await self.loadAllSessions(page: 0)
            }
        }
        self.viewModel.onNextPage = { [weak self] in
            guard let self else { return }
            Task { await self.loadAllSessions(page: self.viewModel.page + 1) }
        }
        self.viewModel.onPrevPage = { [weak self] in
            guard let self else { return }
            Task { await self.loadAllSessions(page: max(0, self.viewModel.page - 1)) }
        }
    }

    public func start() {
        timerTask?.cancel()
        timerTask = Task.detached { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    // Check for changes cheaply
                    let dv = try await self.reader.dataVersion()
                    if dv != self.lastDataVersion {
                        self.lastDataVersion = dv
                        self.stableCycles = 0
                        let snapshot = try await self.reader.fetchLatestUsage()
                        await self.append(snapshot: snapshot)
                        // Also refresh session list (first page)
                        if let sessions = try? await self.reader.fetchSessions(limit: 50, offset: self.sessionsPage * 50) {
                            await self.applySessions(sessions)
                        }
                        // Refresh global totals (aggregated across all sessions)
                        await self.refreshGlobalTotals()
                    } else {
                        self.stableCycles += 1
                    }
                } catch {
                    // TODO: surface error state
                }
                // Adaptive polling based on stability
                let base = max(1, self.settings.updateInterval)
                let interval = min(5, base + min(2, self.stableCycles))
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            }
        }
    }

    deinit { timerTask?.cancel() }

    @MainActor
    private func append(snapshot: UsageSnapshot) async {
        history.append(snapshot)
        if history.count > 360 { history.removeFirst(history.count - 360) }

        let used = snapshot.tokensUsed
        let limit = snapshot.sessionLimitOverride ?? settings.sessionTokenLimit
        let percent = Int(metrics.usagePercent(used: used, limit: limit).rounded())
        let health = metrics.healthState(for: Double(percent))
        let tpm = metrics.tokensPerMinute(history: history)
        let remaining = max(0, limit - used)
        let ttl = metrics.timeToLimit(remaining: remaining, ratePerMin: tpm)

        let costUSD = CostEstimator.estimateUSD(tokens: used, ratePer1k: Double(settings.costRatePer1kTokensUSD))
        let costStr = CostEstimator.formatUSD(costUSD)
        viewModel.update(used: used, remaining: remaining, percent: percent, health: health, tpm: tpm, ttl: ttl, sparkline: historySuffixNormalized(), cost: costStr)
        // Fire notifications if thresholds crossed
        if settings.notificationsEnabled {
            if percent >= settings.criticalThreshold {
                await Notifier.notifyThreshold(percent, level: .ninetyfive)
            } else if percent >= settings.highThreshold {
                await Notifier.notifyThreshold(percent, level: .ninety)
            } else if percent >= settings.warnThreshold {
                await Notifier.notifyThreshold(percent, level: .seventy)
            }
        }
        onUIUpdate?(viewModel)
    }

    private func historySuffixNormalized() -> [Double] {
        let arr = history.suffix(60).map { Double($0.tokensUsed) }
        // convert absolute tokens to deltas per step for nicer sparkline (monotonic growth -> flat line otherwise)
        guard arr.count >= 2 else { return Array(arr) }
        var out: [Double] = [0]
        for i in 1..<arr.count { out.append(max(0, arr[i] - arr[i-1])) }
        return out
    }

    @MainActor
    private func applySessions(_ sessions: [SessionSummary]) async {
        // Heuristic: detect compaction if tokens drop while messages increase
        let now = Date()
        let mapped = sessions.map { s -> SessionSummary in
            let prev = lastSessionMetrics[s.id]
            var state = s.state
            var hasMarker = s.hasCompactionIndicators
            if let prev = prev {
                let usageDrop = prev.usage - s.usagePercent
                let tokensDrop = prev.tokens - s.tokensUsed
                let messagesUp = s.messageCount >= prev.messages
                if (usageDrop >= 10.0 || tokensDrop > (s.contextWindow / 20)) && messagesUp {
                    // significant drop (~10% window or >5% of window tokens) with continued activity
                    compactingUntil[s.id] = now.addingTimeInterval(10) // show spinner for ~10s
                    state = .compacting
                    hasMarker = true
                }
            }
            if let until = compactingUntil[s.id], until > now {
                state = .compacting
                hasMarker = true
            }
            // update metrics cache
            lastSessionMetrics[s.id] = (tokens: s.tokensUsed, messages: s.messageCount, usage: s.usagePercent)
            return SessionSummary(id: s.id, cwd: s.cwd, tokensUsed: s.tokensUsed, contextWindow: s.contextWindow, usagePercent: s.usagePercent, messageCount: s.messageCount, lastActivity: s.lastActivity, state: state, internalRowID: s.internalRowID, hasCompactionIndicators: hasMarker)
        }
        viewModel.sessions = mapped
        // Global totals for header
        let totalTokens = mapped.reduce(0) { $0 + $1.tokensUsed }
        viewModel.totalTokens = totalTokens
        viewModel.totalSessions = mapped.count
        viewModel.sessionsNearLimit = mapped.filter { $0.usagePercent >= 90 }.count
    }

    private func loadAllSessions(page: Int) async {
        do {
            let count = try await reader.sessionCount()
            let offset = page * pageSize
            let sessions = try await reader.fetchSessions(limit: pageSize, offset: offset)
            await MainActor.run {
                viewModel.totalSessionsCount = count
                viewModel.allSessions = sessions
                viewModel.page = page
                viewModel.showAllSheet = true
            }
        } catch {
            // ignore errors for now
        }
    }

    private func refreshGlobalTotals() async {
        do {
            let global = try await reader.fetchGlobalMetrics()
            await MainActor.run {
                viewModel.globalTokens = global.totalTokens
                viewModel.globalSessions = global.totalSessions
                viewModel.globalNearLimit = global.sessionsNearLimit
                viewModel.globalTop = global.topHeavySessions
            }
        } catch { /* ignore */ }
    }
}

public final class UsageViewModel: ObservableObject {
    @Published public private(set) var tokensUsed: Int = 0
    @Published public private(set) var tokensRemaining: Int = 0
    @Published public private(set) var percent: Int = 0
    @Published public private(set) var health: HealthState = .idle
    @Published public private(set) var tokensPerMinute: Double = 0
    @Published public private(set) var timeRemaining: String = "—"
    @Published public private(set) var sparkline: [Double] = []
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var estimatedCost: String = "$—"
    @Published public var sessions: [SessionSummary] = []
    @Published public var totalTokens: Int = 0
    @Published public var totalSessions: Int = 0
    @Published public var sessionsNearLimit: Int = 0
    // Global totals across all sessions
    @Published public var globalTokens: Int = 0
    @Published public var globalSessions: Int = 0
    @Published public var globalNearLimit: Int = 0
    @Published public var globalTop: [SessionSummary] = []
    @Published public var searchQuery: String = ""
    @Published public var sort: SessionSort = .lastActivity
    @Published public var selectedSession: SessionDetails? = nil
    public var onSelectSession: ((SessionSummary) -> Void)? = nil
    // All sessions sheet
    @Published public var showAllSheet: Bool = false
    @Published public var allSessions: [SessionSummary] = []
    @Published public var page: Int = 0
    @Published public var totalSessionsCount: Int = 0
    public var onOpenAll: (() -> Void)? = nil
    public var onNextPage: (() -> Void)? = nil
    public var onPrevPage: (() -> Void)? = nil

    public var subtitle: String { "Live from Amazon Q" }
    public var tintColor: Color {
        switch health {
        case .idle: return .gray
        case .healthy: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
    public func update(used: Int, remaining: Int, percent: Int, health: HealthState, tpm: Double, ttl: TimeInterval?, sparkline: [Double], cost: String) {
        tokensUsed = used
        tokensRemaining = remaining
        self.percent = percent
        self.health = health
        tokensPerMinute = tpm
        if let ttl { timeRemaining = Self.formatTTL(ttl) } else { timeRemaining = "—" }
        self.sparkline = sparkline
        self.estimatedCost = cost
    }

    public func openPreferences() { NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) }
    public func togglePause() { isPaused.toggle() }
    public func quit() { NSApp.terminate(nil) }

    private static func formatTTL(_ v: TimeInterval) -> String {
        let mins = Int(v / 60)
        let hrs = mins / 60
        if hrs > 0 { return "\(hrs)h \(mins % 60)m" }
        return "\(mins)m"
    }
}

#if canImport(SwiftUI)
import SwiftUI
public typealias Color = SwiftUI.Color
extension UsageViewModel {
    public static var preview: UsageViewModel {
        let vm = UsageViewModel()
        vm.update(used: 33000, remaining: 11000, percent: 75, health: .warning, tpm: 250, ttl: 44*60, sparkline: (0..<40).map { _ in Double(Int.random(in: 10...100)) }, cost: "$0.42")
        return vm
    }
}

public enum SessionSort: String, CaseIterable, Sendable {
    case lastActivity
    case usage
    case tokens
    case messages
    case id
}
#endif
