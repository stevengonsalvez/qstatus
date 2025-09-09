import Foundation
import UserNotifications

public enum Threshold: Int, CaseIterable, Sendable {
    case seventy = 70
    case ninety = 90
    case ninetyfive = 95
}

public enum Notifier {
    private static var lastLevelNotified: Int = 0

    static func canUseUserNotifications() -> Bool {
        // UNUserNotificationCenter requires a proper bundled app environment.
        // When running via SwiftPM (no .app bundle), skip to avoid crash.
        if let bid = Bundle.main.bundleIdentifier, !bid.isEmpty { return true }
        let url = Bundle.main.bundleURL
        return url.path.hasSuffix(".app")
    }

    public static func requestAuthorization() async {
        guard canUseUserNotifications() else { return }
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.badge, .alert, .sound])
    }

    public static func notifyThreshold(_ percent: Int, level: Threshold) async {
        guard canUseUserNotifications() else { return }
        guard percent >= level.rawValue else { return }
        // basic cooldown: avoid repeating the same level
        if lastLevelNotified == level.rawValue { return }
        lastLevelNotified = level.rawValue

        let content = UNMutableNotificationContent()
        content.title = "Q-Status"
        content.body = "Usage reached \(percent)% (≥\(level.rawValue)%)"
        content.sound = .default

        let request = UNNotificationRequest(identifier: "qstatus-\(level.rawValue)-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
