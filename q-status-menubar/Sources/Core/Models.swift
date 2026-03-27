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

// MARK: - By-Model Aggregation Types (protocol-level, decoupled from QDBReader)

public struct GlobalByModel: Sendable {
    public let modelId: String?
    public let tokens: Int
    public let messages: Int

    public init(modelId: String?, tokens: Int, messages: Int) {
        self.modelId = modelId
        self.tokens = tokens
        self.messages = messages
    }
}

public struct PeriodByModel: Sendable {
    public let modelId: String?
    public let dayTokens: Int
    public let weekTokens: Int
    public let monthTokens: Int
    public let yearTokens: Int
    public let dayMessages: Int
    public let weekMessages: Int
    public let monthMessages: Int
    public let dayCost: Double
    public let weekCost: Double
    public let monthCost: Double
    public let yearCost: Double

    public init(
        modelId: String?,
        dayTokens: Int,
        weekTokens: Int,
        monthTokens: Int,
        yearTokens: Int,
        dayMessages: Int,
        weekMessages: Int,
        monthMessages: Int
    ) {
        self.modelId = modelId
        self.dayTokens = dayTokens
        self.weekTokens = weekTokens
        self.monthTokens = monthTokens
        self.yearTokens = yearTokens
        self.dayMessages = dayMessages
        self.weekMessages = weekMessages
        self.monthMessages = monthMessages
        self.dayCost = 0.0
        self.weekCost = 0.0
        self.monthCost = 0.0
        self.yearCost = 0.0
    }

    public init(
        modelId: String?,
        dayTokens: Int,
        weekTokens: Int,
        monthTokens: Int,
        yearTokens: Int,
        dayMessages: Int,
        weekMessages: Int,
        monthMessages: Int,
        dayCost: Double,
        weekCost: Double,
        monthCost: Double,
        yearCost: Double
    ) {
        self.modelId = modelId
        self.dayTokens = dayTokens
        self.weekTokens = weekTokens
        self.monthTokens = monthTokens
        self.yearTokens = yearTokens
        self.dayMessages = dayMessages
        self.weekMessages = weekMessages
        self.monthMessages = monthMessages
        self.dayCost = dayCost
        self.weekCost = weekCost
        self.monthCost = monthCost
        self.yearCost = yearCost
    }
}
