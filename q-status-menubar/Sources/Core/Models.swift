import Foundation

public struct UsageSnapshot: Equatable, Sendable {
    public let timestamp: Date
    public let tokensUsed: Int
    public let messageCount: Int
    public let conversationId: String?
    public let sessionLimitOverride: Int?
}

// Per-session rollup used for listing sessions
public enum SessionState: Sendable {
    case normal
    case warn
    case critical
    case compacting
    case compacted
    case error
}

public struct SessionSummary: Identifiable, Sendable {
    public let id: String            // conversation key
    public let cwd: String?          // env_context.env_state.current_working_directory
    public let tokensUsed: Int       // estimated tokens
    public let contextWindow: Int    // default 200_000 if missing
    public let usagePercent: Double  // 0-100
    public let messageCount: Int     // estimated count
    public let lastActivity: Date?   // best-effort (row order proxy)
    public let state: SessionState
    public let internalRowID: Int64?
    public let hasCompactionIndicators: Bool
    public let modelId: String?
    public let costUSD: Double
}

public struct GlobalMetrics: Sendable {
    public let totalSessions: Int
    public let totalTokens: Int
    public let sessionsNearLimit: Int
    public let topHeavySessions: [SessionSummary]
}

public struct SessionDetails: Identifiable, Sendable {
    public var id: String { summary.id }
    public let summary: SessionSummary
    public let historyTokens: Int
    public let contextFilesTokens: Int
    public let toolsTokens: Int
    public let systemTokens: Int
}

public enum HealthState: Sendable {
    case idle
    case healthy
    case warning
    case critical
}
