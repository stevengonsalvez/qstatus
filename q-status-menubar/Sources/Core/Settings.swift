import Foundation
import Combine
import Yams

public enum ClaudePlan: String, CaseIterable, Codable {
    case free
    case starter
    case pro
    case enterprise
    case custom

    public var displayName: String {
        switch self {
        case .free: return "Free"
        case .starter: return "Starter"
        case .pro: return "Pro"
        case .enterprise: return "Enterprise"
        case .custom: return "Custom"
        }
    }

    /// Approximate monthly cost cap in USD. Enterprise uses 0 to indicate no fixed cap.
    public var costLimit: Double {
        switch self {
        case .free: return 0
        case .starter: return 120
        case .pro: return 400
        case .enterprise: return 0
        case .custom: return 0
        }
    }

    /// Approximate session token budget (context window) for plan defaults.
    public var tokenLimit: Int {
        switch self {
        case .free: return 0
        case .starter: return 200_000
        case .pro: return 400_000
        case .enterprise: return 600_000
        case .custom: return 0
        }
    }

    /// Informational monthly message guideline for UI display.
    public var messageLimit: Int {
        switch self {
        case .free: return 0
        case .starter: return 5_000
        case .pro: return 25_000
        case .enterprise: return 0
        case .custom: return 0
        }
    }
}

public enum ClaudeViewMode: String, CaseIterable, Codable {
    case compact
    case expanded
}

public final class SettingsStore: ObservableObject {
    @Published public var updateInterval: Int = 3
    @Published public var showPercentBadge: Bool = true
    @Published public var launchAtLogin: Bool = false

    @Published public var notificationsEnabled: Bool = true
    @Published public var warnThreshold: Int = 70
    @Published public var highThreshold: Int = 90
    @Published public var criticalThreshold: Int = 95

    public enum ColorScheme: String, CaseIterable {
        case auto, light, dark
    }
    @Published public var colorScheme: ColorScheme = .auto

    // Token limit configuration (placeholder)
    @Published public var sessionTokenLimit: Int = 44_000
    // Default context window for conversations
    @Published public var defaultContextWindowTokens: Int = 175_000
    // Cost estimation
    @Published public var costRatePer1kTokensUSD: Double = 0.0066
    @Published public var costModelName: String = "q-default"
    @Published public var modelPricing: [String: Double] = [:]
    @Published public var costMode: String = CostMode.auto.rawValue

    // Filters & grouping
    @Published public var groupByFolder: Bool = false
    @Published public var refreshIntervalSeconds: Int = 3

    // Menubar icon configuration
    public enum IconMode: String, CaseIterable { case mostRecent, pinned, frontmostTerminal, monthlyMessages }
    @Published public var iconMode: IconMode = .mostRecent
    @Published public var pinnedSessionKey: String? = nil
    @Published public var showActiveBadge: Bool = true

    // UI density
    @Published public var compactMode: Bool = true

    // Data source management
    @Published public var dataSourceType: DataSourceType = .amazonQ
    @Published public var claudeConfigPaths: [String] = SettingsStore.defaultClaudeConfigPaths()

    // Claude plan management
    @Published public var claudePlan: ClaudePlan = .free
    @Published public var claudeViewMode: ClaudeViewMode = .compact
    @Published public var customPlanTokenLimit: Int = 200_000
    @Published public var customPlanCostLimit: Double = 150.0

    public init() {
        loadFromDisk()
        applyEnvironmentOverrides()
    }

    public func loadFromDisk() {
        let url = configURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            if let text = String(data: data, encoding: .utf8) {
                if let dict = try Yams.load(yaml: text) as? [String: Any] {
                    if let interval = dict["polling_interval_seconds"] as? Int { self.updateInterval = interval }
                    if let show = dict["show_percent_badge"] as? Bool { self.showPercentBadge = show }
                    if let login = dict["launch_at_login"] as? Bool { self.launchAtLogin = login }
                    if let notif = dict["notifications_enabled"] as? Bool { self.notificationsEnabled = notif }
                    if let warn = dict["warn_threshold"] as? Int { self.warnThreshold = warn }
                    if let high = dict["high_threshold"] as? Int { self.highThreshold = high }
                    if let critical = dict["critical_threshold"] as? Int { self.criticalThreshold = critical }
                    if let scheme = dict["color_scheme"] as? String { self.colorScheme = ColorScheme(rawValue: scheme) ?? .auto }
                    if let limit = dict["session_token_limit"] as? Int { self.sessionTokenLimit = limit }
                    if let defaultCtx = dict["default_context_window_tokens"] as? Int { self.defaultContextWindowTokens = defaultCtx }
                    if let rate = dict["cost_rate_per_1k_tokens_usd"] as? Double { self.costRatePer1kTokensUSD = rate }
                    if let model = dict["cost_model_name"] as? String { self.costModelName = model }
                    if let mp = dict["model_pricing"] as? [String: Any] {
                        var out: [String: Double] = [:]
                        for (k,v) in mp { if let dv = v as? Double { out[k] = dv } }
                        self.modelPricing = out
                    }
                    if let gb = dict["group_by_folder"] as? Bool { self.groupByFolder = gb }
                    if let ref = dict["refresh_interval_seconds"] as? Int { self.refreshIntervalSeconds = ref }
                    if let im = dict["icon_mode"] as? String { self.iconMode = IconMode(rawValue: im) ?? .mostRecent }
                    if let pin = dict["pinned_session_key"] as? String { self.pinnedSessionKey = pin }
                    if let badge = dict["show_active_badge"] as? Bool { self.showActiveBadge = badge }
                    if let compact = dict["compact_mode"] as? Bool { self.compactMode = compact }
                    if let pricingMode = dict["claude_cost_mode"] as? String { self.costMode = pricingMode }
                    if let ds = dict["data_source_type"] as? String, let parsed = DataSourceType(rawValue: ds) { self.dataSourceType = parsed }
                    if let paths = dict["claude_config_paths"] as? [Any] {
                        self.claudeConfigPaths = paths.compactMap { $0 as? String }
                    } else if let csv = dict["claude_config_paths"] as? String {
                        self.claudeConfigPaths = csv.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    }
                    if let planRaw = dict["claude_plan"] as? String, let plan = ClaudePlan(rawValue: planRaw) { self.claudePlan = plan }
                    if let viewModeRaw = dict["claude_view_mode"] as? String, let mode = ClaudeViewMode(rawValue: viewModeRaw) { self.claudeViewMode = mode }
                    if let customTokenLimit = dict["claude_custom_token_limit"] as? Int { self.customPlanTokenLimit = customTokenLimit }
                    if let customCostLimit = dict["claude_custom_cost_limit"] as? Double { self.customPlanCostLimit = customCostLimit }
                }
            }
        } catch {
            // ignore, keep defaults
        }
    }

    public func saveToDisk() {
        let url = configURL()
        let dict: [String: Any] = [
            "polling_interval_seconds": updateInterval,
            "show_percent_badge": showPercentBadge,
            "launch_at_login": launchAtLogin,
            "notifications_enabled": notificationsEnabled,
            "warn_threshold": warnThreshold,
            "high_threshold": highThreshold,
            "critical_threshold": criticalThreshold,
            "color_scheme": colorScheme.rawValue,
            "session_token_limit": sessionTokenLimit,
            "default_context_window_tokens": defaultContextWindowTokens,
            "cost_rate_per_1k_tokens_usd": costRatePer1kTokensUSD,
            "cost_model_name": costModelName,
            "model_pricing": modelPricing,
            "claude_cost_mode": costMode,
            "group_by_folder": groupByFolder,
            "refresh_interval_seconds": refreshIntervalSeconds,
            "icon_mode": iconMode.rawValue,
            "pinned_session_key": pinnedSessionKey as Any,
            "show_active_badge": showActiveBadge,
            "compact_mode": compactMode,
            "data_source_type": dataSourceType.rawValue,
            "claude_config_paths": claudeConfigPaths,
            "claude_plan": claudePlan.rawValue,
            "claude_view_mode": claudeViewMode.rawValue,
            "claude_custom_token_limit": customPlanTokenLimit,
            "claude_custom_cost_limit": customPlanCostLimit
        ]
        do {
            let yaml = try Yams.dump(object: dict)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try yaml.data(using: .utf8)?.write(to: url)
        } catch {
            // ignore for now
        }
    }

    public func applyEnvironmentOverrides() {
        let env = ProcessInfo.processInfo.environment
        if let s = env["QSTATUS_POLL_INTERVAL"], let v = Int(s) { updateInterval = v }
        if let s = env["QSTATUS_SHOW_BADGE"], let v = Bool(fromString: s) { showPercentBadge = v }
        if let s = env["QSTATUS_LAUNCH_AT_LOGIN"], let v = Bool(fromString: s) { launchAtLogin = v }
        if let s = env["QSTATUS_NOTIFICATIONS"], let v = Bool(fromString: s) { notificationsEnabled = v }
        if let s = env["QSTATUS_THRESH_WARN"], let v = Int(s) { warnThreshold = v }
        if let s = env["QSTATUS_THRESH_HIGH"], let v = Int(s) { highThreshold = v }
        if let s = env["QSTATUS_THRESH_CRIT"], let v = Int(s) { criticalThreshold = v }
        if let s = env["QSTATUS_TOKEN_LIMIT"], let v = Int(s) { sessionTokenLimit = v }
        if let s = env["QSTATUS_DEFAULT_CTX_WINDOW"], let v = Int(s) { defaultContextWindowTokens = v }
        if let s = env["QSTATUS_COST_RATE_1K"], let v = Double(s) { costRatePer1kTokensUSD = v }
        if let s = env["QSTATUS_COST_MODEL" ] { costModelName = s }
        if let s = env["QSTATUS_CLAUDE_COST_MODE"], let mode = CostMode(rawValue: s) { costMode = mode.rawValue }
        if let s = env["QSTATUS_GROUP_BY_FOLDER"], let v = Bool(fromString: s) { groupByFolder = v }
        if let s = env["QSTATUS_REFRESH_SECS"], let v = Int(s) { refreshIntervalSeconds = v }
        if let s = env["QSTATUS_ICON_MODE"], let v = IconMode(rawValue: s) { iconMode = v }
        if let s = env["QSTATUS_PINNED_SESSION"], !s.isEmpty { pinnedSessionKey = s }
        if let s = env["QSTATUS_BADGE_ACTIVE"], let v = Bool(fromString: s) { showActiveBadge = v }
        if let s = env["QSTATUS_COMPACT"], let v = Bool(fromString: s) { compactMode = v }
        if let s = env["QSTATUS_DATA_SOURCE"], let v = DataSourceType(rawValue: s) { dataSourceType = v }
        if let s = env["QSTATUS_CLAUDE_PLAN"], let v = ClaudePlan(rawValue: s) { claudePlan = v }
        if let s = env["QSTATUS_CLAUDE_VIEW_MODE"], let v = ClaudeViewMode(rawValue: s) { claudeViewMode = v }
        if let s = env["QSTATUS_CLAUDE_CONFIG_DIRS"], !s.isEmpty {
            claudeConfigPaths = s.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let s = env["QSTATUS_CLAUDE_TOKEN_LIMIT"], let v = Int(s) { customPlanTokenLimit = v }
        if let s = env["QSTATUS_CLAUDE_COST_LIMIT"], let v = Double(s) { customPlanCostLimit = v }
    }

    private func configURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/q-status/config.yaml")
    }

    public var claudeTokenLimit: Int {
        switch claudePlan {
        case .free: return 0
        case .custom: return customPlanTokenLimit
        default: return claudePlan.tokenLimit
        }
    }

    public var claudeCostLimit: Double {
        switch claudePlan {
        case .custom: return customPlanCostLimit
        default: return claudePlan.costLimit
        }
    }

    public func claudeTokenLimitPercentage(currentTokens: Int) -> Double {
        let limit = claudeTokenLimit
        guard limit > 0 else { return 0 }
        let pct = (Double(currentTokens) / Double(limit)) * 100.0
        return min(100.0, max(0.0, pct))
    }

    public func isApproachingClaudeLimit(currentTokens: Int) -> Bool {
        claudeTokenLimitPercentage(currentTokens: currentTokens) >= 80.0
    }

    private static func defaultClaudeConfigPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".config/claude").path,
            home.appendingPathComponent(".claude").path
        ]
    }
}

private extension Bool {
    init?(fromString s: String) {
        switch s.lowercased() {
        case "1","true","yes","y","on": self = true
        case "0","false","no","n","off": self = false
        default: return nil
        }
    }
}
