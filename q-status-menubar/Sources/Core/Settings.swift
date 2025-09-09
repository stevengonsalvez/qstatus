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
    // Cost estimation
    @Published public var costRatePer1kTokensUSD: Double = 0.0025
    @Published public var costModelName: String = "q-default"

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
                    if let rate = dict["cost_rate_per_1k_tokens_usd"] as? Double { self.costRatePer1kTokensUSD = rate }
                    if let model = dict["cost_model_name"] as? String { self.costModelName = model }
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
            "cost_rate_per_1k_tokens_usd": costRatePer1kTokensUSD,
            "cost_model_name": costModelName
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
        if let s = env["QSTATUS_COST_RATE_1K"], let v = Double(s) { costRatePer1kTokensUSD = v }
        if let s = env["QSTATUS_COST_MODEL" ] { costModelName = s }
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
