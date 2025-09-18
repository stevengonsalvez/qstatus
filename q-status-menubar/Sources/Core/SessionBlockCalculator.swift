// ABOUTME: SessionBlockCalculator groups Claude usage entries into 5-hour billing blocks
// This file implements the session block algorithm for grouping usage data into time-based blocks with gap detection

import Foundation

/// Default session duration in hours (Claude's billing block duration)
public let DEFAULT_SESSION_DURATION_HOURS: Double = 5

/// Represents a session block (typically 5-hour billing period) with usage data
public struct SessionBlock: Sendable {
    public let id: String // ISO string of block start time
    public let startTime: Date
    public let endTime: Date // startTime + 5 hours (for normal blocks) or gap end time (for gap blocks)
    public let actualEndTime: Date? // Last activity in block
    public let isActive: Bool
    public let isGap: Bool // True if this is a gap block
    public let entries: [ClaudeUsageEntry]
    public let tokenCounts: TokenCounts
    public let costUSD: Double
    public let models: Set<String>

    public init(
        id: String,
        startTime: Date,
        endTime: Date,
        actualEndTime: Date? = nil,
        isActive: Bool = false,
        isGap: Bool = false,
        entries: [ClaudeUsageEntry] = [],
        tokenCounts: TokenCounts = TokenCounts(),
        costUSD: Double = 0,
        models: Set<String> = []
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.actualEndTime = actualEndTime
        self.isActive = isActive
        self.isGap = isGap
        self.entries = entries
        self.tokenCounts = tokenCounts
        self.costUSD = costUSD
        self.models = models
    }
}

/// Aggregated token counts for different token types
public struct TokenCounts: Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationInputTokens: Int
    public let cacheReadInputTokens: Int

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheCreationInputTokens: Int = 0,
        cacheReadInputTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }

    /// Calculate total tokens
    public var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationInputTokens + cacheReadInputTokens
    }
}

/// Calculator for grouping usage entries into session blocks
public struct SessionBlockCalculator {

    /// Floors a timestamp to the beginning of the hour in UTC
    /// - Parameter date: The date to floor
    /// - Returns: New Date object floored to the UTC hour
    private static func floorToHour(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return calendar.date(from: components) ?? date
    }

    /// Identifies and creates session blocks from usage entries
    /// Groups entries into time-based blocks (typically 5-hour periods) with gap detection
    /// - Parameters:
    ///   - entries: Array of usage entries to process
    ///   - sessionDurationHours: Duration of each session block in hours
    /// - Returns: Array of session blocks with aggregated usage data
    public static func identifySessionBlocks(
        entries: [ClaudeUsageEntry],
        sessionDurationHours: Double = DEFAULT_SESSION_DURATION_HOURS
    ) -> [SessionBlock] {
        guard !entries.isEmpty else {
            return []
        }

        let sessionDurationSeconds = sessionDurationHours * 60 * 60
        var blocks: [SessionBlock] = []

        // Sort entries by timestamp
        let sortedEntries = entries.sorted { entry1, entry2 in
            guard let date1 = entry1.date, let date2 = entry2.date else {
                return false
            }
            return date1 < date2
        }

        var currentBlockStart: Date?
        var currentBlockEntries: [ClaudeUsageEntry] = []
        let now = Date()

        for entry in sortedEntries {
            guard let entryTime = entry.date else { continue }

            if currentBlockStart == nil {
                // First entry - start a new block (floored to the hour)
                currentBlockStart = floorToHour(entryTime)
                currentBlockEntries = [entry]
            } else if let blockStart = currentBlockStart {
                let timeSinceBlockStart = entryTime.timeIntervalSince(blockStart)

                if let lastEntry = currentBlockEntries.last,
                   let lastEntryTime = lastEntry.date {
                    let timeSinceLastEntry = entryTime.timeIntervalSince(lastEntryTime)

                    if timeSinceBlockStart > sessionDurationSeconds || timeSinceLastEntry > sessionDurationSeconds {
                        // Close current block
                        let block = createBlock(
                            startTime: blockStart,
                            entries: currentBlockEntries,
                            now: now,
                            sessionDurationSeconds: sessionDurationSeconds
                        )
                        blocks.append(block)

                        // Add gap block if there's a significant gap
                        if timeSinceLastEntry > sessionDurationSeconds {
                            if let gapBlock = createGapBlock(
                                lastActivityTime: lastEntryTime,
                                nextActivityTime: entryTime,
                                sessionDurationSeconds: sessionDurationSeconds
                            ) {
                                blocks.append(gapBlock)
                            }
                        }

                        // Start new block (floored to the hour)
                        currentBlockStart = floorToHour(entryTime)
                        currentBlockEntries = [entry]
                    } else {
                        // Add to current block
                        currentBlockEntries.append(entry)
                    }
                }
            }
        }

        // Close the last block
        if let blockStart = currentBlockStart, !currentBlockEntries.isEmpty {
            let block = createBlock(
                startTime: blockStart,
                entries: currentBlockEntries,
                now: now,
                sessionDurationSeconds: sessionDurationSeconds
            )
            blocks.append(block)
        }

        return blocks
    }

    /// Creates a session block from a start time and usage entries
    /// - Parameters:
    ///   - startTime: When the block started
    ///   - entries: Usage entries in this block
    ///   - now: Current time for active block detection
    ///   - sessionDurationSeconds: Session duration in seconds
    /// - Returns: Session block with aggregated data
    private static func createBlock(
        startTime: Date,
        entries: [ClaudeUsageEntry],
        now: Date,
        sessionDurationSeconds: TimeInterval
    ) -> SessionBlock {
        let endTime = startTime.addingTimeInterval(sessionDurationSeconds)
        let actualEndTime = entries.last?.date ?? startTime
        let isActive = now.timeIntervalSince(actualEndTime) < sessionDurationSeconds && now < endTime

        // Aggregate token counts
        var inputTokens = 0
        var outputTokens = 0
        var cacheCreationInputTokens = 0
        var cacheReadInputTokens = 0
        var costUSD = 0.0
        var models = Set<String>()

        for entry in entries {
            inputTokens += entry.message.usage.input_tokens
            outputTokens += entry.message.usage.output_tokens
            cacheCreationInputTokens += entry.message.usage.cache_creation_input_tokens ?? 0
            cacheReadInputTokens += entry.message.usage.cache_read_input_tokens ?? 0
            costUSD += entry.costUSD ?? 0

            if let model = entry.message.model {
                models.insert(model)
            }
        }

        let tokenCounts = TokenCounts(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationInputTokens: cacheCreationInputTokens,
            cacheReadInputTokens: cacheReadInputTokens
        )

        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")

        return SessionBlock(
            id: formatter.string(from: startTime),
            startTime: startTime,
            endTime: endTime,
            actualEndTime: actualEndTime,
            isActive: isActive,
            isGap: false,
            entries: entries,
            tokenCounts: tokenCounts,
            costUSD: costUSD,
            models: models
        )
    }

    /// Creates a gap block representing periods with no activity
    /// - Parameters:
    ///   - lastActivityTime: Time of last activity before gap
    ///   - nextActivityTime: Time of next activity after gap
    ///   - sessionDurationSeconds: Session duration in seconds
    /// - Returns: Gap block or nil if gap is too short
    private static func createGapBlock(
        lastActivityTime: Date,
        nextActivityTime: Date,
        sessionDurationSeconds: TimeInterval
    ) -> SessionBlock? {
        // Only create gap blocks for gaps longer than the session duration
        let gapDuration = nextActivityTime.timeIntervalSince(lastActivityTime)
        guard gapDuration > sessionDurationSeconds else {
            return nil
        }

        let gapStart = lastActivityTime.addingTimeInterval(sessionDurationSeconds)
        let gapEnd = nextActivityTime

        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")

        return SessionBlock(
            id: "gap-\(formatter.string(from: gapStart))",
            startTime: gapStart,
            endTime: gapEnd,
            actualEndTime: nil,
            isActive: false,
            isGap: true,
            entries: [],
            tokenCounts: TokenCounts(),
            costUSD: 0,
            models: []
        )
    }
}

/// Burn rate calculations for session blocks
public struct BurnRateCalculator {

    /// Represents usage burn rate calculations
    public struct BurnRate {
        public let tokensPerMinute: Double
        public let tokensPerMinuteForIndicator: Double
        public let costPerHour: Double
    }

    /// Calculates the burn rate (tokens/minute and cost/hour) for a session block
    /// - Parameter block: Session block to analyze
    /// - Returns: Burn rate calculations or nil if block has no activity
    public static func calculateBurnRate(for block: SessionBlock) -> BurnRate? {
        guard !block.entries.isEmpty, !block.isGap else {
            return nil
        }

        guard let firstEntry = block.entries.first?.date,
              let lastEntry = block.entries.last?.date else {
            return nil
        }

        let durationMinutes = lastEntry.timeIntervalSince(firstEntry) / 60

        guard durationMinutes > 0 else {
            return nil
        }

        let totalTokens = Double(block.tokenCounts.totalTokens)
        let tokensPerMinute = totalTokens / durationMinutes

        // For burn rate indicator, use only input and output tokens
        let nonCacheTokens = Double(block.tokenCounts.inputTokens + block.tokenCounts.outputTokens)
        let tokensPerMinuteForIndicator = nonCacheTokens / durationMinutes

        let costPerHour = (block.costUSD / durationMinutes) * 60

        return BurnRate(
            tokensPerMinute: tokensPerMinute,
            tokensPerMinuteForIndicator: tokensPerMinuteForIndicator,
            costPerHour: costPerHour
        )
    }
}

/// Projected usage calculations
public struct ProjectedUsageCalculator {

    /// Represents projected usage for remaining time in a session block
    public struct ProjectedUsage {
        public let totalTokens: Int
        public let totalCost: Double
        public let remainingMinutes: Int
    }

    /// Projects total usage for an active session block based on current burn rate
    /// - Parameter block: Active session block to project
    /// - Returns: Projected usage totals or nil if block is inactive or has no burn rate
    public static func projectBlockUsage(for block: SessionBlock) -> ProjectedUsage? {
        guard block.isActive, !block.isGap else {
            return nil
        }

        guard let burnRate = BurnRateCalculator.calculateBurnRate(for: block) else {
            return nil
        }

        let now = Date()
        let remainingTime = block.endTime.timeIntervalSince(now)
        let remainingMinutes = max(0, remainingTime / 60)

        let currentTokens = Double(block.tokenCounts.totalTokens)
        let projectedAdditionalTokens = burnRate.tokensPerMinute * remainingMinutes
        let totalTokens = currentTokens + projectedAdditionalTokens

        let projectedAdditionalCost = (burnRate.costPerHour / 60) * remainingMinutes
        let totalCost = block.costUSD + projectedAdditionalCost

        return ProjectedUsage(
            totalTokens: Int(round(totalTokens)),
            totalCost: round(totalCost * 100) / 100,
            remainingMinutes: Int(round(remainingMinutes))
        )
    }
}

/// Filter utilities for session blocks
public struct SessionBlockFilter {

    /// Filters session blocks to include only recent ones and active blocks
    /// - Parameters:
    ///   - blocks: Array of session blocks to filter
    ///   - days: Number of recent days to include (default: 3)
    /// - Returns: Filtered array of recent or active blocks
    public static func filterRecentBlocks(_ blocks: [SessionBlock], days: Int = 3) -> [SessionBlock] {
        let now = Date()
        let cutoffTime = now.addingTimeInterval(-Double(days * 24 * 60 * 60))

        return blocks.filter { block in
            // Include block if it started after cutoff or if it's still active
            block.startTime >= cutoffTime || block.isActive
        }
    }
}