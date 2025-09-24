import Foundation
import Combine
import Yams

// Claude subscription plan types matching Claude-Code-Usage-Monitor
public enum ClaudePlan: String, CaseIterable, Codable {
    case free = "free"
    case pro = "pro"       // 19K tokens, $18/month, 1000 messages
    case max5 = "max5"     // 88K tokens, $35/month, 5000 messages
    case max20 = "max20"   // 220K tokens, $140/month, 20000 messages
    case custom = "custom" // P90-based limits

    // Token limits per plan
    public var tokenLimit: Int {
        switch self {
        case .free: return 0
        case .pro: return 19_000
        case .max5: return 88_000
        case .max20: return 220_000
        case .custom: return 200_000  // Default, calculated via P90
        }
    }

    // Cost limits per plan
    public var costLimit: Double {
        switch self {
        case .free: return 0
        case .pro: return 18.0
        case .max5: return 35.0
        case .max20: return 140.0
        case .custom: return 100.0  // Default, calculated via P90
        }
    }

    // Message limits per plan
    public var messageLimit: Int {
        switch self {
        case .free: return 0
        case .pro: return 1000
        case .max5: return 5000
        case .max20: return 20000
        case .custom: return 10000  // Default, calculated via P90
        }
    }

    public var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro ($18/mo)"
        case .max5: return "Max 5 ($35/mo)"
        case .max20: return "Max 20 ($140/mo)"
        case .custom: return "Custom (P90)"
        }
    }

    public var monthlyLimit: Double {
        return costLimit
    }
}

// Claude Code view mode
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
    // Claude Code specific token limits
    @Published public var claudeTokenLimit: Int = 200_000
    @Published public var claudeTokenWarningThreshold: Double = 0.8  // Warning at 80%
    @Published public var claudePlan: ClaudePlan = .free

    // Custom plan P90 settings
    @Published public var customPlanP90Percentile: Double = 90.0
    @Published public var customPlanUseP90: Bool = true
    @Published public var customPlanTokenLimit: Int = 200_000
    @Published public var customPlanCostLimit: Double = 100.0
    @Published public var customPlanMessageLimit: Int = 10000

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

    // Claude Code view mode
    @Published public var claudeViewMode: ClaudeViewMode = .compact

    // Provider configuration
    @Published public var dataSourceType: DataSourceType = .amazonQ
    @Published public var claudeConfigPaths: [String] = SettingsStore.defaultClaudeConfigPaths()

    // Computed property to check if approaching Claude token limit
    public func isApproachingClaudeLimit(currentTokens: Int) -> Bool {
        let percentage = Double(currentTokens) / Double(claudeTokenLimit)
        return percentage >= claudeTokenWarningThreshold
    }

    public func claudeTokenLimitPercentage(currentTokens: Int) -> Double {
        return PercentageCalculator.calculateTokenPercentage(
            tokens: currentTokens,
            limit: claudeTokenLimit,
            cappedAt100: false
        )
    }

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
                    if let claudeLimit = dict["claude_token_limit"] as? Int { self.claudeTokenLimit = claudeLimit }
                    if let claudeThreshold = dict["claude_token_warning_threshold"] as? Double { self.claudeTokenWarningThreshold = claudeThreshold }
                    if let plan = dict["claude_plan"] as? String { self.claudePlan = ClaudePlan(rawValue: plan) ?? .free }
                    if let customP90 = dict["custom_plan_p90_percentile"] as? Double { self.customPlanP90Percentile = customP90 }
                    if let customUseP90 = dict["custom_plan_use_p90"] as? Bool { self.customPlanUseP90 = customUseP90 }
                    if let customTokens = dict["custom_plan_token_limit"] as? Int { self.customPlanTokenLimit = customTokens }
                    if let customCost = dict["custom_plan_cost_limit"] as? Double { self.customPlanCostLimit = customCost }
                    if let customMessages = dict["custom_plan_message_limit"] as? Int { self.customPlanMessageLimit = customMessages }
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
                    if let viewMode = dict["claude_view_mode"] as? String { self.claudeViewMode = ClaudeViewMode(rawValue: viewMode) ?? .compact }
                    if let dsType = dict["data_source_type"] as? String { self.dataSourceType = DataSourceType(rawValue: dsType) ?? .amazonQ }
                    if let paths = dict["claude_config_paths"] as? [Any] {
                        self.claudeConfigPaths = paths.compactMap { $0 as? String }
                    } else if let csv = dict["claude_config_paths"] as? String {
                        self.claudeConfigPaths = csv.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    }
                    if let mode = dict["cost_mode"] as? String { self.costMode = mode }
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
            "claude_token_limit": claudeTokenLimit,
            "claude_token_warning_threshold": claudeTokenWarningThreshold,
            "claude_plan": claudePlan.rawValue,
            "custom_plan_p90_percentile": customPlanP90Percentile,
            "custom_plan_use_p90": customPlanUseP90,
            "custom_plan_token_limit": customPlanTokenLimit,
            "custom_plan_cost_limit": customPlanCostLimit,
            "custom_plan_message_limit": customPlanMessageLimit,
            "cost_rate_per_1k_tokens_usd": costRatePer1kTokensUSD,
            "cost_model_name": costModelName,
            "model_pricing": modelPricing,
            "cost_mode": costMode,
            "group_by_folder": groupByFolder,
            "refresh_interval_seconds": refreshIntervalSeconds,
            "icon_mode": iconMode.rawValue,
            "pinned_session_key": pinnedSessionKey as Any,
            "show_active_badge": showActiveBadge,
            "compact_mode": compactMode,
            "claude_view_mode": claudeViewMode.rawValue,
            "data_source_type": dataSourceType.rawValue,
            "claude_config_paths": claudeConfigPaths
        ]
        do {
            let yaml = try Yams.dump(object: dict)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try yaml.data(using: .utf8)?.write(to: url)
        } catch {
            // ignore for now
        }
    }

    private func applyEnvironmentOverrides() {
        let env = ProcessInfo.processInfo.environment
        if let s = env["QSTATUS_POLL_SECS"], let v = Int(s) { updateInterval = v }
        if let s = env["QSTATUS_SHOW_PERCENT"], let v = Bool(fromString: s) { showPercentBadge = v }
        if let s = env["QSTATUS_LAUNCH_LOGIN"], let v = Bool(fromString: s) { launchAtLogin = v }
        if let s = env["QSTATUS_NOTIFY"], let v = Bool(fromString: s) { notificationsEnabled = v }
        if let s = env["QSTATUS_WARN"], let v = Int(s) { warnThreshold = v }
        if let s = env["QSTATUS_HIGH"], let v = Int(s) { highThreshold = v }
        if let s = env["QSTATUS_CRIT"], let v = Int(s) { criticalThreshold = v }
        if let s = env["QSTATUS_COLOR_SCHEME"], let v = ColorScheme(rawValue: s) { colorScheme = v }
        if let s = env["QSTATUS_SESSION_TOKEN_LIMIT"], let v = Int(s) { sessionTokenLimit = v }
        if let s = env["QSTATUS_DEFAULT_CTX_WINDOW"], let v = Int(s) { defaultContextWindowTokens = v }
        if let s = env["QSTATUS_COST_RATE_1K"], let v = Double(s) { costRatePer1kTokensUSD = v }
        if let s = env["QSTATUS_COST_MODEL" ] { costModelName = s }
        if let s = env["QSTATUS_GROUP_BY_FOLDER"], let v = Bool(fromString: s) { groupByFolder = v }
        if let s = env["QSTATUS_REFRESH_SECS"], let v = Int(s) { refreshIntervalSeconds = v }
        if let s = env["QSTATUS_ICON_MODE"], let v = IconMode(rawValue: s) { iconMode = v }
        if let s = env["QSTATUS_PINNED_SESSION"], !s.isEmpty { pinnedSessionKey = s }
        if let s = env["QSTATUS_BADGE_ACTIVE"], let v = Bool(fromString: s) { showActiveBadge = v }
        if let s = env["QSTATUS_COMPACT"], let v = Bool(fromString: s) { compactMode = v }
        if let s = env["QSTATUS_DATA_SOURCE"] {
            if s == "amazon-q" { dataSourceType = .amazonQ }
            else if s == "claude-code" { dataSourceType = .claudeCode }
        }
        if let s = env["QSTATUS_CLAUDE_CONFIG_PATHS"] {
            claudeConfigPaths = s.split(separator: ":").map(String.init)
        }
        if let s = env["QSTATUS_COST_MODE"] { costMode = s }
        if let s = env["QSTATUS_CLAUDE_PLAN"], let v = ClaudePlan(rawValue: s) { claudePlan = v }
        if let s = env["QSTATUS_CLAUDE_VIEW_MODE"], let v = ClaudeViewMode(rawValue: s) { claudeViewMode = v }
        if let s = env["QSTATUS_CLAUDE_TOKEN_LIMIT"], let v = Int(s) { claudeTokenLimit = v }
        if let s = env["QSTATUS_CLAUDE_COST_LIMIT"], let v = Double(s) { customPlanCostLimit = v }
    }

    private func configURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/q-status/config.yaml")
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
        case "true", "yes", "1": self = true
        case "false", "no", "0": self = false
        default: return nil
        }
    }
}