// ABOUTME: Data models for Codex CLI rate limits and session data.
// Codex exposes rate_limit percentages (not token counts) via JSONL session files.

import Foundation

public struct CodexRateLimits: Sendable, Equatable {
    public let primaryUsedPercent: Double       // 0-100, 5h window
    public let primaryWindowMinutes: Int        // 300 = 5h
    public let primaryResetsAt: Date

    public let secondaryUsedPercent: Double     // 0-100, 7d window
    public let secondaryWindowMinutes: Int      // 10080 = 7d
    public let secondaryResetsAt: Date

    public let creditsBalance: Double?          // nil if unlimited or no credits
    public let creditsUnlimited: Bool

    public let planType: String                 // "pro", "max", etc.

    public init(
        primaryUsedPercent: Double,
        primaryWindowMinutes: Int,
        primaryResetsAt: Date,
        secondaryUsedPercent: Double,
        secondaryWindowMinutes: Int,
        secondaryResetsAt: Date,
        creditsBalance: Double?,
        creditsUnlimited: Bool,
        planType: String
    ) {
        self.primaryUsedPercent = primaryUsedPercent
        self.primaryWindowMinutes = primaryWindowMinutes
        self.primaryResetsAt = primaryResetsAt
        self.secondaryUsedPercent = secondaryUsedPercent
        self.secondaryWindowMinutes = secondaryWindowMinutes
        self.secondaryResetsAt = secondaryResetsAt
        self.creditsBalance = creditsBalance
        self.creditsUnlimited = creditsUnlimited
        self.planType = planType
    }
}

public struct CodexSessionData: Sendable, Equatable {
    public let rateLimits: CodexRateLimits?
    public let cwd: String?
    public let model: String?
    public let sessionId: String?
    public let lastActivity: Date
    public let isActive: Bool                   // modified within last hour

    public init(
        rateLimits: CodexRateLimits?,
        cwd: String?,
        model: String?,
        sessionId: String?,
        lastActivity: Date,
        isActive: Bool
    ) {
        self.rateLimits = rateLimits
        self.cwd = cwd
        self.model = model
        self.sessionId = sessionId
        self.lastActivity = lastActivity
        self.isActive = isActive
    }

    /// Truncate a full path to ~/relative form for display.
    public var displayCwd: String? {
        guard let cwd else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if cwd.hasPrefix(home) {
            return "~" + cwd.dropFirst(home.count)
        }
        return cwd
    }
}

/// Display-ready Codex quota data for the menubar UI.
public struct CodexDisplayData: Sendable, Equatable {
    public struct RateItem: Sendable, Equatable {
        public let label: String
        public let usedPercent: Double
        public let windowDescription: String     // "5h window" or "7d window"
        public let resetsAt: Date

        public init(label: String, usedPercent: Double, windowDescription: String, resetsAt: Date) {
            self.label = label
            self.usedPercent = usedPercent
            self.windowDescription = windowDescription
            self.resetsAt = resetsAt
        }
    }

    public let primary: RateItem?
    public let secondary: RateItem?
    public let creditsBalance: Double?           // nil if unlimited
    public let creditsUnlimited: Bool
    public let planType: String
    public let cwd: String?                      // truncated display cwd
    public let model: String?
    public let isActive: Bool
    public let lastActivity: Date
    public let updatedAt: Date

    public init(
        primary: RateItem?,
        secondary: RateItem?,
        creditsBalance: Double?,
        creditsUnlimited: Bool,
        planType: String,
        cwd: String?,
        model: String?,
        isActive: Bool,
        lastActivity: Date,
        updatedAt: Date
    ) {
        self.primary = primary
        self.secondary = secondary
        self.creditsBalance = creditsBalance
        self.creditsUnlimited = creditsUnlimited
        self.planType = planType
        self.cwd = cwd
        self.model = model
        self.isActive = isActive
        self.lastActivity = lastActivity
        self.updatedAt = updatedAt
    }
}
