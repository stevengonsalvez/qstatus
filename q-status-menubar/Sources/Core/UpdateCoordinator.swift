import Foundation
import AppKit

public final class UpdateCoordinator: @unchecked Sendable {
    public var reader: any DataSource
    public let metrics: MetricsCalculator
    public let settings: SettingsStore

    public var onUIUpdate: ((UsageViewModel) -> Void)?
    public let viewModel: UsageViewModel

    private var timerTask: Task<Void, Never>?
    private var isRunning = false
    private var history: [UsageSnapshot] = []
    private var lastDataVersion: Int = -1
    private var stableCycles: Int = 0
    private var sessionsPage: Int = 0
    private let pageSize: Int = 50
    // Active Claude Code session tracking
    private var activeClaudeSession: ActiveSessionData?
    // Compaction heuristics
    private var lastSessionMetrics: [String: (tokens: Int, messages: Int, usage: Double)] = [:]
    private var compactingUntil: [String: Date] = [:]
    // Global EMA rates
    private var lastGlobalTokens: Int = 0
    private var lastGlobalRateAt: Date = .distantPast
    private var emaTokensPerMinute: Double = 0
    private let emaAlpha: Double = 0.3

    public init(reader: any DataSource, metrics: MetricsCalculator, settings: SettingsStore) {
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
        isRunning = true
        timerTask = Task.detached { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.isRunning {
                do {
                    // Check for changes cheaply
                    let dv = try await self.reader.dataVersion()
                    if dv != self.lastDataVersion {
                        self.lastDataVersion = dv
                        self.stableCycles = 0
                        let snapshot = try await self.reader.fetchLatestUsage()
                        await self.append(snapshot: snapshot)
                        // Also refresh session list (first page)
                        if let sessions = try? await self.reader.fetchSessions(limit: 50, offset: self.sessionsPage * 50, groupByFolder: self.settings.groupByFolder, activeOnly: false) {
                            await self.applySessions(sessions)
                        }
                        // Refresh global totals (aggregated across all sessions)
                        await self.refreshGlobalTotals()
                        // Refresh active Claude Code session if applicable
                        await self.refreshActiveClaudeSession()
                    } else {
                        self.stableCycles += 1
                    }
                } catch {
                    // TODO: surface error state
                }
                // Adaptive polling based on stability
                let base = max(1, self.settings.refreshIntervalSeconds)
                let interval = min(5, base + min(2, self.stableCycles))
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            }
        }
    }

    // Manual refresh bypassing data_version gate
    public func manualRefresh() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await self.reader.fetchLatestUsage()
                await self.append(snapshot: snapshot)
                if let sessions = try? await self.reader.fetchSessions(limit: 50, offset: self.sessionsPage * 50, groupByFolder: self.settings.groupByFolder, activeOnly: false) {
                    await self.applySessions(sessions)
                }
                await self.refreshGlobalTotals()
                await self.refreshActiveClaudeSession()
            } catch { /* ignore */ }
        }
    }

    public func stop() {
        isRunning = false
        timerTask?.cancel()
        timerTask = nil
    }

    public func restart(with newDataSource: any DataSource) async {
        // Stop current polling
        stop()

        // Clear cached data to force fresh fetch
        lastDataVersion = -1
        stableCycles = 0
        history = []
        lastSessionMetrics = [:]
        compactingUntil = [:]
        lastGlobalTokens = 0
        lastGlobalRateAt = .distantPast
        emaTokensPerMinute = 0

        // Update the data source
        reader = newDataSource

        // Clear view model state
        await MainActor.run {
            viewModel.sessions = []
            viewModel.globalTop = []
            viewModel.sessionCategoryTokens = [:]
            viewModel._lastGlobalTotalTokens = nil
            viewModel._lastTotalsDate = nil
        }

        // Start polling with new data source
        start()

        // Force immediate refresh
        manualRefresh()
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
            // Compute per-session cost with model-specific override when available
            let rate = self.settings.modelPricing[s.modelId ?? ""] ?? self.settings.costRatePer1kTokensUSD
            let cost = CostEstimator.estimateUSD(tokens: s.tokensUsed, ratePer1k: rate)
            // Use 175k base for context usage percent (per Q CLI display)
            let contextBase = 175_000
            // Cap at 99.9% unless truly at or above limit
            let rawUsage = (Double(s.tokensUsed)/Double(contextBase))*100.0
            let usage175 = s.tokensUsed >= contextBase ? 100.0 : min(99.9, max(0.0, rawUsage))
            return SessionSummary(id: s.id, cwd: s.cwd, tokensUsed: s.tokensUsed, contextWindow: contextBase, usagePercent: usage175, messageCount: s.messageCount, lastActivity: s.lastActivity, state: state, internalRowID: s.internalRowID, hasCompactionIndicators: hasMarker, modelId: s.modelId, costUSD: cost)
        }
        viewModel.sessions = mapped
        // Global totals for header
        let totalTokens = mapped.reduce(0) { $0 + $1.tokensUsed }
        viewModel.totalTokens = totalTokens
        viewModel.totalSessions = mapped.count
        viewModel.sessionsNearLimit = mapped.filter { $0.usagePercent >= 90 }.count
        // Per-session cost accumulation
        let pageCost = mapped.reduce(0.0) { $0 + sToCost($1) }
        viewModel.pageCost = CostEstimator.formatUSD(pageCost)
        // Preload category breakdown for first few rows to render stacked bars
        Task.detached { [weak self] in
            guard let self else { return }
            let firstKeys = mapped.prefix(10).map { $0.id }
            await withTaskGroup(of: (String, (Int,Int,Int,Int))?.self) { group in
                for key in firstKeys {
                    group.addTask { [weak self] in
                        guard let self else { return nil }
                        if let details = try? await self.reader.fetchSessionDetail(key: key) {
                            return (key, (details.historyTokens, details.contextFilesTokens, details.toolsTokens, details.systemTokens))
                        }
                        return nil
                    }
                }
                var updatesLocal: [String:(Int,Int,Int,Int)] = [:]
                for await res in group { if let (k, tuple) = res { updatesLocal[k] = tuple } }
                let safeUpdates = updatesLocal
                await MainActor.run { for (k,t) in safeUpdates { self.viewModel.sessionCategoryTokens[k] = (history:t.0, context:t.1, tools:t.2, system:t.3) } }
            }
        }
    }

    private func sToCost(_ s: SessionSummary) -> Double {
        let rate = self.settings.modelPricing[s.modelId ?? ""] ?? self.settings.costRatePer1kTokensUSD
        return CostEstimator.estimateUSD(tokens: s.tokensUsed, ratePer1k: rate)
    }

    private func loadAllSessions(page: Int) async {
        do {
            let count = try await reader.sessionCount(activeOnly: false)
            let offset = page * pageSize
            // For all sessions view, never group by folder - show individual sessions
            let sessions = try await reader.fetchSessions(limit: pageSize, offset: offset, groupByFolder: false, activeOnly: false)
            // compute costs for allSessions
            let costMapped = sessions.map { s -> SessionSummary in
                let rate = self.settings.modelPricing[s.modelId ?? ""] ?? self.settings.costRatePer1kTokensUSD
                let cost = CostEstimator.estimateUSD(tokens: s.tokensUsed, ratePer1k: rate)
                return SessionSummary(id: s.id, cwd: s.cwd, tokensUsed: s.tokensUsed, contextWindow: s.contextWindow, usagePercent: s.usagePercent, messageCount: s.messageCount, lastActivity: s.lastActivity, state: s.state, internalRowID: s.internalRowID, hasCompactionIndicators: s.hasCompactionIndicators, modelId: s.modelId, costUSD: cost)
            }
            await MainActor.run {
                viewModel.totalSessionsCount = count
                viewModel.allSessions = costMapped
                viewModel.page = page
                viewModel.showAllSheet = true
            }
            // Compute precise day/week/month for this page subset
            let keys = sessions.map { $0.id }
            if let perModel = try? await reader.fetchPeriodTokensByModel(forKeys: keys) {
                var dTok = 0, wTok = 0, mTok = 0
                var dCost = 0.0, wCost = 0.0, mCost = 0.0
                for row in perModel {
                    let rate = self.settings.modelPricing[row.modelId ?? ""] ?? self.settings.costRatePer1kTokensUSD
                    dTok += row.dayTokens; wTok += row.weekTokens; mTok += row.monthTokens
                    dCost += CostEstimator.estimateUSD(tokens: row.dayTokens, ratePer1k: rate)
                    wCost += CostEstimator.estimateUSD(tokens: row.weekTokens, ratePer1k: rate)
                    mCost += CostEstimator.estimateUSD(tokens: row.monthTokens, ratePer1k: rate)
                }
                let finalDTok = dTok
                let finalWTok = wTok
                let finalMTok = mTok
                let finalDCost = dCost
                let finalWCost = wCost
                let finalMCost = mCost
                await MainActor.run {
                    viewModel.sheetTokensDay = finalDTok
                    viewModel.sheetTokensWeek = finalWTok
                    viewModel.sheetTokensMonth = finalMTok
                    viewModel.sheetCostDay = finalDCost
                    viewModel.sheetCostWeek = finalWCost
                    viewModel.sheetCostMonth = finalMCost
                }
            }
        } catch {
            // ignore errors for now
        }
    }

    private func refreshGlobalTotals() async {
        do {
            let global = try await reader.fetchGlobalMetrics()
            let byModel = (try? await reader.fetchGlobalTotalsByModel()) ?? []
            // Compute precise totals and cost from by-model rows
            var totalTokens = 0
            var totalMessages = 0
            var totalCost = 0.0
            for row in byModel {
                totalTokens += row.tokens
                totalMessages += row.messages
                let rate = self.settings.modelPricing[row.modelId ?? ""] ?? self.settings.costRatePer1kTokensUSD
                totalCost += CostEstimator.estimateUSD(tokens: row.tokens, ratePer1k: rate)
            }
            let finalTotalTokens = totalTokens
            let finalTotalMessages = totalMessages
            let finalTotalCost = totalCost
            await MainActor.run {
                viewModel.globalTokens = finalTotalTokens
                viewModel.globalMessages = finalTotalMessages
                viewModel.globalCost = finalTotalCost
                viewModel.globalSessions = global.totalSessions
                viewModel.globalNearLimit = global.sessionsNearLimit
                viewModel.globalTop = global.topHeavySessions
                // Update EMA burn rate from global total delta
                let now = Date()
                if lastGlobalRateAt != .distantPast {
                    let dt = now.timeIntervalSince(lastGlobalRateAt)
                    if dt > 0 {
                        let dTokens = max(0, finalTotalTokens - lastGlobalTokens)
                        let instPerMin = (Double(dTokens) / dt) * 60.0
                        emaTokensPerMinute = emaAlpha * instPerMin + (1.0 - emaAlpha) * emaTokensPerMinute
                        viewModel.globalTokensPerMinute = emaTokensPerMinute
                    }
                }
                lastGlobalRateAt = now
                lastGlobalTokens = finalTotalTokens
                // Snapshot-delta accumulation for Today/Week/Month (approximate)
                let delta = max(0, finalTotalTokens - (viewModel._lastGlobalTotalTokens ?? 0))
                viewModel._lastGlobalTotalTokens = finalTotalTokens
                let now2 = Date()
                if Calendar.current.isDateInToday(viewModel._lastTotalsDate ?? now2) == false {
                    viewModel.tokensToday = 0; viewModel.costToday = 0
                    viewModel._lastTotalsDate = now2
                }
                // Delta accumulation removed - will get precise values from fetchPeriodTokensByModel
            }
            // Precise day/week/month tokens+messages per model, then cost via pricing
            if let perModel = try? await reader.fetchPeriodTokensByModel() {
                var dayTok = 0, weekTok = 0, monthTok = 0, yearTok = 0
                var dayMsg = 0, weekMsg = 0, monthMsg = 0
                var dayCost = 0.0, weekCost = 0.0, monthCost = 0.0, yearCost = 0.0
                var weightedRateNumerator: Double = 0.0
                var weightedRateDenominator: Int = 0
                for row in perModel {
                    dayTok += row.dayTokens; weekTok += row.weekTokens; monthTok += row.monthTokens; yearTok += row.yearTokens
                    dayMsg += row.dayMessages; weekMsg += row.weekMessages; monthMsg += row.monthMessages
                    // Use costs directly from the data source (already calculated with correct JSONL costs)
                    dayCost += row.dayCost
                    weekCost += row.weekCost
                    monthCost += row.monthCost
                    yearCost += row.yearCost
                    // Weighted average rate per 1k based on day tokens
                    let rate = row.dayTokens > 0 ? (row.dayCost * 1000.0 / Double(row.dayTokens)) : self.settings.costRatePer1kTokensUSD
                    weightedRateNumerator += Double(row.dayTokens) * rate
                    weightedRateDenominator += row.dayTokens
                }
                let dTok = dayTok, wTok = weekTok, mTok = monthTok, yTok = yearTok
                let dC = dayCost, wC = weekCost, mC = monthCost, yC = yearCost, _ = monthMsg
                let wrNum = weightedRateNumerator, wrDen = weightedRateDenominator
                await MainActor.run {
                    viewModel.tokensToday = dTok
                    viewModel.tokensWeek = wTok
                    viewModel.tokensMonth = mTok
                    viewModel.tokensYear = yTok
                    viewModel.costToday = dC
                    viewModel.costWeek = wC
                    viewModel.costMonth = mC
                    viewModel.costYear = yC
                    // We'll override messagesMonth below with history-based count
                    if wrDen > 0 {
                        viewModel.weightedRatePer1k = wrNum / Double(wrDen)
                    } else {
                        viewModel.weightedRatePer1k = self.settings.costRatePer1kTokensUSD
                    }
                }
            }
            // History-based monthly message count (authoritative locally)
            if let mCount = try? await reader.fetchMonthlyMessageCount() {
                await MainActor.run { viewModel.messagesMonth = mCount }
            }
            // Enrich Top 5 with precise tokens/cwd using details; cap usage at 100%
            let enrichedTop = try await withThrowingTaskGroup(of: SessionSummary?.self) { group -> [SessionSummary] in
                for s in (viewModel.globalTop.prefix(5)) {
                    group.addTask { [weak self] in
                        guard let self else { return s }
                        if let details = try? await self.reader.fetchSessionDetail(key: s.id) {
                            let ctxBase = 175_000
                            let tokens = details.summary.tokensUsed
                            // Cap at 99.9% unless truly at or above limit
                            let rawUsage = (Double(tokens)/Double(ctxBase))*100.0
                            let usage = tokens >= ctxBase ? 100.0 : min(99.9, max(0.0, rawUsage))
                            let cwd = details.summary.cwd
                            let rate = self.settings.modelPricing[details.summary.modelId ?? ""] ?? self.settings.costRatePer1kTokensUSD
                            let cost = CostEstimator.estimateUSD(tokens: tokens, ratePer1k: rate)
                            return SessionSummary(id: s.id, cwd: cwd, tokensUsed: tokens, contextWindow: ctxBase, usagePercent: usage, messageCount: details.summary.messageCount, lastActivity: details.summary.lastActivity, state: usage >= 100 ? .critical : (usage >= 90 ? .warn : .normal), internalRowID: s.internalRowID, hasCompactionIndicators: s.hasCompactionIndicators, modelId: details.summary.modelId, costUSD: cost)
                        }
                        return s
                    }
                }
                var out: [SessionSummary] = []
                for try await item in group { if let i = item { out.append(i) } }
                return out
            }
            await MainActor.run { viewModel.globalTop = enrichedTop }
        } catch { /* ignore */ }
    }

    private func refreshActiveClaudeSession() async {
        // Only fetch active session for Claude Code data source
        guard settings.dataSourceType == .claudeCode else {
            await MainActor.run { viewModel.activeClaudeSession = nil }
            return
        }

        // Check if reader is ClaudeCodeDataSource and fetch active session
        if let claudeReader = reader as? ClaudeCodeDataSource {
            do {
                let activeSession = try await claudeReader.fetchActiveSession()
                await MainActor.run {
                    viewModel.activeClaudeSession = activeSession
                }
            } catch {
                await MainActor.run {
                    viewModel.activeClaudeSession = nil
                }
            }
        }
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
    @Published public var pageCost: String = "$—"
    // Global totals across all sessions
    @Published public var globalTokens: Int = 0
    @Published public var globalSessions: Int = 0
    @Published public var globalNearLimit: Int = 0
    @Published public var globalTop: [SessionSummary] = []
    @Published public var globalMessages: Int = 0
    @Published public var globalCost: Double = 0
    // Period metrics (approximate via snapshot deltas)
    @Published public var tokensToday: Int = 0
    @Published public var tokensWeek: Int = 0
    @Published public var tokensMonth: Int = 0
    @Published public var tokensYear: Int = 0
    @Published public var costToday: Double = 0
    @Published public var costWeek: Double = 0
    @Published public var costMonth: Double = 0
    @Published public var costYear: Double = 0
    @Published public var messagesMonth: Int = 0
    // Global burn/cost rate
    @Published public var globalTokensPerMinute: Double = 0
    @Published public var weightedRatePer1k: Double = 0.0025
    // Internal trackers
    public var _lastGlobalTotalTokens: Int? = nil
    public var _lastTotalsDate: Date? = nil
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
    // Sheet footer period totals
    @Published public var sheetTokensDay: Int = 0
    @Published public var sheetTokensWeek: Int = 0
    @Published public var sheetTokensMonth: Int = 0
    @Published public var sheetCostDay: Double = 0
    @Published public var sheetCostWeek: Double = 0
    @Published public var sheetCostMonth: Double = 0
    // Access to settings for UI toggles
    public var settings: SettingsStore? = nil
    public var forceRefresh: (() -> Void)? = nil
    // Cached per-session category tokens for stacked bars
    @Published public var sessionCategoryTokens: [String: (history:Int, context:Int, tools:Int, system:Int)] = [:]
    // Provider switching state
    @Published public var isSwitchingProvider: Bool = false
    // Provider switch callback
    public var onSwitchProvider: ((DataSourceType) async -> Void)? = nil
    // Active Claude Code session
    @Published public var activeClaudeSession: ActiveSessionData? = nil

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

    public func openPreferences() {
        print("[DEBUG] openPreferences called")

        // For menubar-only apps, we need to temporarily change the activation policy
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Now try to open the preferences window
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }

        // After a delay, restore the menubar-only policy
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if NSApp.windows.filter({ $0.isVisible && !$0.className.contains("NSStatusBarWindow") }).isEmpty {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
    public func togglePause() { isPaused.toggle() }
    public func quit() { NSApp.terminate(nil) }

    public func switchProvider(to provider: DataSourceType) {
        Task { @MainActor in
            isSwitchingProvider = true
            await onSwitchProvider?(provider)
            isSwitchingProvider = false
        }
    }

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
