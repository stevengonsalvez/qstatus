import Foundation
import Combine
import Yams

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
            "group_by_folder": groupByFolder,
            "refresh_interval_seconds": refreshIntervalSeconds,
            "icon_mode": iconMode.rawValue,
            "pinned_session_key": pinnedSessionKey as Any,
            "show_active_badge": showActiveBadge,
            "compact_mode": compactMode
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
        if let s = env["QSTATUS_GROUP_BY_FOLDER"], let v = Bool(fromString: s) { groupByFolder = v }
        if let s = env["QSTATUS_REFRESH_SECS"], let v = Int(s) { refreshIntervalSeconds = v }
        if let s = env["QSTATUS_ICON_MODE"], let v = IconMode(rawValue: s) { iconMode = v }
        if let s = env["QSTATUS_PINNED_SESSION"], !s.isEmpty { pinnedSessionKey = s }
        if let s = env["QSTATUS_BADGE_ACTIVE"], let v = Bool(fromString: s) { showActiveBadge = v }
        if let s = env["QSTATUS_COMPACT"], let v = Bool(fromString: s) { compactMode = v }
    }

    private func configURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/q-status/config.yaml")
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
