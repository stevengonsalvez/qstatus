// ABOUTME: ClaudeCodeDataSource implements the DataSource protocol for Claude Code JSONL usage data
// This file reads and aggregates usage data from Claude Code transcript files for display in the menubar app

import Foundation
import OSLog

// MARK: - Data Structures

/// Token usage breakdown for a single Claude interaction
public struct ClaudeTokenUsage: Codable, Sendable {
    public let input_tokens: Int
    public let output_tokens: Int
    public let cache_creation_input_tokens: Int?
    public let cache_read_input_tokens: Int?

    /// Calculate total tokens used
    public var totalTokens: Int {
        input_tokens + output_tokens + (cache_creation_input_tokens ?? 0) + (cache_read_input_tokens ?? 0)
    }
}

/// Message structure from Claude JSONL files
public struct ClaudeMessage: Codable, Sendable {
    public let usage: ClaudeTokenUsage
    public let model: String?
    public let id: String?
}

/// Single usage entry from Claude JSONL files
public struct ClaudeUsageEntry: Codable, Sendable {
    public let timestamp: String  // ISO 8601 format
    public let sessionId: String?
    public let message: ClaudeMessage
    public let costUSD: Double?
    public let requestId: String?
    public let cwd: String?  // Current working directory
    public let version: String?  // Claude Code version
    public let isApiErrorMessage: Bool?

    /// Parse timestamp to Date
    public var date: Date? {
        // Try with fractional seconds first (most common in JSONL)
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractional.date(from: timestamp) {
            return date
        }

        // Fall back to standard format without fractional seconds
        let standardFormatter = ISO8601DateFormatter()
        return standardFormatter.date(from: timestamp)
    }
}

/// Active session data for displaying current Claude Code usage
public struct ActiveSessionData: Sendable {
    public let sessionId: String
    public let startTime: Date
    public let lastActivity: Date
    public let tokens: Int  // Context tokens (current session memory after compaction)
    public let cumulativeTokens: Int  // Total tokens used across all messages
    public let cost: Double
    public let isActive: Bool
    public let messageCount: Int
    public let cwd: String?
    public let model: String?
    public let costFromJSONL: Bool  // True if cost came from costUSD field
    public let messagesPerHour: Double  // Burn rate for messages
    public let tokensPerHour: Double    // Burn rate for tokens
    public let costPerHour: Double      // Burn rate for cost in USD

    // Session block information
    public let currentBlock: SessionBlock?  // Current 5-hour billing block
    public let blockNumber: Int  // Which block number this is (1-based)
    public let totalBlocks: Int  // Total number of blocks in this session
}

/// Aggregated session data
public struct ClaudeSession: Sendable {
    public let id: String
    public let startTime: Date
    public let endTime: Date
    public let entries: [ClaudeUsageEntry]
    public let totalInputTokens: Int
    public let totalOutputTokens: Int
    public let totalCacheCreationTokens: Int
    public let totalCacheReadTokens: Int
    public let totalCost: Double
    public let totalCostFromJSONL: Double  // Total cost from costUSD fields
    public let models: Set<String>
    public let cwd: String?
    public let messageCount: Int

    /// Total tokens across all categories
    public var totalTokens: Int {
        totalInputTokens + totalOutputTokens + totalCacheCreationTokens + totalCacheReadTokens
    }
}

// MARK: - ClaudeCodeDataSource Implementation

/// DataSource implementation for Claude Code usage data
public actor ClaudeCodeDataSource: DataSource {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.qstatus", category: "ClaudeCodeDataSource")
    private var sessions: [String: ClaudeSession] = [:]
    private var lastModificationTimes: [String: Date] = [:]
    private var dataVersion: Int = 0
    private var isInitialized = false

    // Configuration
    private let configPaths: [String]
    private let costMode: CostMode

    // Default context window for Claude models
    private let defaultContextWindow = 200_000

    // Cached value for percentage calculations
    private var cachedMaxTokensFromPreviousBlocks: Int? = nil

    // MARK: - Initialization

    public init(configPaths: [String] = [], costMode: CostMode = .auto) {
        self.configPaths = configPaths
        self.costMode = costMode
    }

    // MARK: - DataSource Protocol Implementation

    public func openIfNeeded() async throws {
        guard !isInitialized else { return }

        logger.info("Initializing ClaudeCodeDataSource")
        try await loadAllData()
        isInitialized = true
    }

    /// Fetches the currently active Claude Code session (within last 5 hours)
    public func fetchActiveSession() async throws -> ActiveSessionData? {
        try await openIfNeeded()

        let now = Date()
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)

        // Find sessions that have had activity within the last 5 hours
        let recentSessions = sessions.values.filter { session in
            session.endTime >= fiveHoursAgo
        }.sorted { $0.endTime > $1.endTime }

        guard let mostRecent = recentSessions.first else {
            return nil
        }

        // Check if this session is truly active (last activity within 30 minutes)
        let isActive = mostRecent.endTime >= now.addingTimeInterval(-30 * 60)

        // Calculate how much cost comes from JSONL vs calculated
        var costFromJSONL: Double = 0
        for entry in mostRecent.entries {
            if let cost = entry.costUSD {
                costFromJSONL += cost
            }
        }

        // For active sessions, show the actual context usage from the most recent entry
        // cache_read_input_tokens represents what's actually in Claude's memory right now
        // cache_creation_input_tokens represents new additions to the cache
        let currentContextTokens: Int
        if let lastEntry = mostRecent.entries.last {
            // Use the cache_read_input_tokens as the actual context in use
            // This is what Claude has in memory after compaction
            let cacheReadTokens = lastEntry.message.usage.cache_read_input_tokens ?? 0
            let cacheCreationTokens = lastEntry.message.usage.cache_creation_input_tokens ?? 0
            let inputTokens = lastEntry.message.usage.input_tokens
            // The actual context is: input tokens + cache being read + any new cache being created
            currentContextTokens = inputTokens + cacheReadTokens + cacheCreationTokens
        } else {
            // Fallback if no entries (shouldn't happen for active session)
            currentContextTokens = 0
        }

        // Calculate cumulative tokens - sum of ALL entries' total tokens (input + output + cache)
        let cumulativeTokens = mostRecent.entries.reduce(0) { sum, entry in
            sum + entry.message.usage.totalTokens
        }

        // Calculate session blocks for this session first
        let sessionBlocks = SessionBlockCalculator.identifySessionBlocks(entries: mostRecent.entries)

        // Find current block (the one that contains the current time or is most recent)
        let currentBlock: SessionBlock?
        let blockNumber: Int
        let totalBlocks = sessionBlocks.count

        if let activeBlock = sessionBlocks.first(where: { $0.isActive }) {
            currentBlock = activeBlock
            blockNumber = sessionBlocks.firstIndex(where: { $0.id == activeBlock.id })! + 1
        } else if let lastBlock = sessionBlocks.last {
            // If no active block, use the most recent one
            currentBlock = lastBlock
            blockNumber = sessionBlocks.count
        } else {
            currentBlock = nil
            blockNumber = 0
        }

        // Calculate burn rates from the current block if available
        let tokensPerHour: Double
        let costPerHour: Double
        let messagesPerHour: Double

        if let block = currentBlock,
           let burnRate = BurnRateCalculator.calculateBurnRate(for: block) {
            // Use burn rate from current 5-hour block
            tokensPerHour = burnRate.tokensPerMinute * 60  // Convert to per hour
            costPerHour = burnRate.costPerHour

            // Calculate messages per hour from block
            let blockDuration = block.actualEndTime?.timeIntervalSince(block.startTime) ?? 0
            let blockHours = max(0.01, blockDuration / 3600.0)
            messagesPerHour = Double(block.entries.count) / blockHours
        } else {
            // Fallback to session-wide rates if no block data
            let sessionDuration = mostRecent.endTime.timeIntervalSince(mostRecent.startTime)
            let hoursElapsed = max(0.01, sessionDuration / 3600.0)
            messagesPerHour = Double(mostRecent.messageCount) / hoursElapsed
            tokensPerHour = Double(cumulativeTokens) / hoursElapsed
            let sessionCost = mostRecent.totalCostFromJSONL > 0 ? mostRecent.totalCostFromJSONL : mostRecent.totalCost
            costPerHour = sessionCost / hoursElapsed
        }

        // Note: currentBlock, blockNumber, and totalBlocks already calculated above

        return ActiveSessionData(
            sessionId: mostRecent.id,
            startTime: mostRecent.startTime,
            lastActivity: mostRecent.endTime,
            tokens: currentContextTokens,
            cumulativeTokens: cumulativeTokens,
            cost: calculateCumulativeCost(sessions: recentSessions),
            isActive: isActive,
            messageCount: mostRecent.messageCount,
            cwd: mostRecent.cwd,
            model: mostRecent.models.first,
            costFromJSONL: hasCostsFromJSONL(sessions: recentSessions),
            messagesPerHour: messagesPerHour,
            tokensPerHour: tokensPerHour,
            costPerHour: costPerHour,
            currentBlock: currentBlock,
            blockNumber: blockNumber,
            totalBlocks: totalBlocks
        )
    }

    private func calculateCumulativeCost(sessions: [ClaudeSession]) -> Double {
        return sessions.reduce(0.0) { sum, session in
            sum + (session.totalCostFromJSONL > 0 ? session.totalCostFromJSONL : session.totalCost)
        }
    }

    private func hasCostsFromJSONL(sessions: [ClaudeSession]) -> Bool {
        return sessions.contains { session in
            session.totalCostFromJSONL > 0
        }
    }

    public func dataVersion() async throws -> Int {
        try await openIfNeeded()

        // Check if any files have been modified
        let currentVersion = await checkForFileChanges()
        if currentVersion != dataVersion {
            dataVersion = currentVersion
            try await loadAllData()
        }

        return dataVersion
    }

    public func fetchLatestUsage(window: TimeInterval?) async throws -> UsageSnapshot {
        try await openIfNeeded()

        // Get the most recent session
        guard let latestSession = sessions.values.max(by: { $0.endTime < $1.endTime }) else {
            return UsageSnapshot(
                timestamp: Date(),
                tokensUsed: 0,
                messageCount: 0,
                conversationId: nil,
                sessionLimitOverride: nil
            )
        }

        return UsageSnapshot(
            timestamp: latestSession.endTime,
            tokensUsed: latestSession.totalTokens,
            messageCount: latestSession.messageCount,
            conversationId: latestSession.id,
            sessionLimitOverride: nil
        )
    }

    public func fetchSessions(
        limit: Int,
        offset: Int,
        groupByFolder: Bool,
        activeOnly: Bool
    ) async throws -> [SessionSummary] {
        try await openIfNeeded()

        // Refresh the cached max tokens value
        cachedMaxTokensFromPreviousBlocks = getMaxTokensFromPreviousBlocks()

        var summaries: [SessionSummary] = []

        // Sort sessions by end time (most recent first)
        let sortedSessions = sessions.values.sorted { $0.endTime > $1.endTime }

        // Apply pagination
        let startIndex = min(offset, sortedSessions.count)
        let endIndex = min(startIndex + limit, sortedSessions.count)

        for session in sortedSessions[startIndex..<endIndex] {
            // Calculate context tokens from the latest entry (like fetchActiveSession does)
            let contextTokens: Int
            if let latestEntry = session.entries.last {
                // The actual context is: input tokens + cache being read + any new cache being created
                let inputTokens = latestEntry.message.usage.input_tokens
                let cacheReadTokens = latestEntry.message.usage.cache_read_input_tokens ?? 0
                let cacheCreationTokens = latestEntry.message.usage.cache_creation_input_tokens ?? 0
                contextTokens = inputTokens + cacheReadTokens + cacheCreationTokens
            } else {
                // Fallback if no entries
                contextTokens = 0
            }

            // Get the current block for this session if it exists
            let blocks = SessionBlockCalculator.identifySessionBlocks(entries: session.entries)
            let currentBlock = blocks.first { $0.isActive } ?? blocks.last

            // Use the new centralized calculator
            let usagePercent = PercentageCalculator.calculateSessionPercentage(
                session: session,
                currentBlock: currentBlock,
                maxTokensFromPreviousBlocks: cachedMaxTokensFromPreviousBlocks
            )
            let state = getSessionState(usagePercent: usagePercent)

            // Use JSONL cost if available, otherwise fall back to calculated cost
            let sessionCost = session.totalCostFromJSONL > 0 ? session.totalCostFromJSONL : session.totalCost

            summaries.append(SessionSummary(
                id: session.id,
                cwd: session.cwd,
                tokensUsed: contextTokens,  // Use context tokens, not cumulative
                contextWindow: defaultContextWindow,
                usagePercent: usagePercent,
                messageCount: session.messageCount,
                lastActivity: session.endTime,
                state: state,
                internalRowID: nil,
                hasCompactionIndicators: false,
                modelId: session.models.first,
                costUSD: sessionCost
            ))
        }

        return summaries
    }

    public func fetchSessionDetail(key: String) async throws -> SessionDetails? {
        try await openIfNeeded()

        guard let session = sessions[key] else { return nil }

        // Calculate context tokens from the latest entry (like fetchActiveSession does)
        let contextTokens: Int
        if let latestEntry = session.entries.last {
            // The actual context is: input tokens + cache being read + any new cache being created
            let inputTokens = latestEntry.message.usage.input_tokens
            let cacheReadTokens = latestEntry.message.usage.cache_read_input_tokens ?? 0
            let cacheCreationTokens = latestEntry.message.usage.cache_creation_input_tokens ?? 0
            contextTokens = inputTokens + cacheReadTokens + cacheCreationTokens
        } else {
            // Fallback if no entries
            contextTokens = 0
        }

        // Get the current block for this session if it exists
        let blocks = SessionBlockCalculator.identifySessionBlocks(entries: session.entries)
        let currentBlock = blocks.first { $0.isActive } ?? blocks.last

        // Use the new centralized calculator
        let usagePercent = PercentageCalculator.calculateSessionPercentage(
            session: session,
            currentBlock: currentBlock,
            maxTokensFromPreviousBlocks: cachedMaxTokensFromPreviousBlocks ?? getMaxTokensFromPreviousBlocks()
        )
        let state = getSessionState(usagePercent: usagePercent)

        // Use JSONL cost if available, otherwise fall back to calculated cost
        let sessionCost = session.totalCostFromJSONL > 0 ? session.totalCostFromJSONL : session.totalCost

        let summary = SessionSummary(
            id: session.id,
            cwd: session.cwd,
            tokensUsed: contextTokens,  // Use context tokens, not cumulative
            contextWindow: defaultContextWindow,
            usagePercent: usagePercent,
            messageCount: session.messageCount,
            lastActivity: session.endTime,
            state: state,
            internalRowID: nil,
            hasCompactionIndicators: false,
            modelId: session.models.first,
            costUSD: sessionCost
        )

        // For Claude Code, we don't have detailed token breakdown
        // so we distribute tokens proportionally
        let historyTokens = session.totalInputTokens
        let contextFilesTokens = 0  // Not available in Claude Code data
        let toolsTokens = 0  // Not available in Claude Code data
        let systemTokens = session.totalCacheReadTokens + session.totalCacheCreationTokens

        return SessionDetails(
            summary: summary,
            historyTokens: historyTokens,
            contextFilesTokens: contextFilesTokens,
            toolsTokens: toolsTokens,
            systemTokens: systemTokens
        )
    }

    public func sessionCount(activeOnly: Bool) async throws -> Int {
        try await openIfNeeded()

        if activeOnly {
            // Consider sessions from last 24 hours as active
            let cutoff = Date().addingTimeInterval(-86400)
            return sessions.values.filter { $0.endTime > cutoff }.count
        }

        return sessions.count
    }

    public func fetchGlobalMetrics(limitForTop: Int) async throws -> GlobalMetrics {
        try await openIfNeeded()

        let totalSessions = sessions.count
        let totalTokens = sessions.values.reduce(0) { $0 + $1.totalTokens }

        // Count sessions near limit (>80% usage)
        let maxFromPrevious = cachedMaxTokensFromPreviousBlocks ?? getMaxTokensFromPreviousBlocks()
        let sessionsNearLimit = sessions.values.filter { session in
            // Get blocks for this session
            let blocks = SessionBlockCalculator.identifySessionBlocks(entries: session.entries)
            let currentBlock = blocks.first { $0.isActive } ?? blocks.last

            let usagePercent = PercentageCalculator.calculateSessionPercentage(
                session: session,
                currentBlock: currentBlock,
                maxTokensFromPreviousBlocks: maxFromPrevious
            )
            return usagePercent > 80
        }.count

        // Get top heavy sessions
        let topSessions = try await fetchSessions(
            limit: limitForTop,
            offset: 0,
            groupByFolder: false,
            activeOnly: false
        )

        return GlobalMetrics(
            totalSessions: totalSessions,
            totalTokens: totalTokens,
            sessionsNearLimit: sessionsNearLimit,
            topHeavySessions: topSessions
        )
    }

    /// Get the maximum tokens from all previous (completed) session blocks
    public func getMaxTokensFromPreviousBlocks() -> Int? {
        // Get all sessions
        let allSessions = sessions.values

        // Collect all blocks from all sessions
        var allBlocks: [SessionBlock] = []
        for session in allSessions {
            let blocks = SessionBlockCalculator.identifySessionBlocks(entries: session.entries)
            allBlocks.append(contentsOf: blocks)
        }

        // Filter out active and gap blocks, find max
        let maxTokens = allBlocks
            .filter { !$0.isActive && !$0.isGap }
            .map { $0.tokenCounts.totalTokens }
            .max()

        return maxTokens
    }

    // MARK: - Optional Protocol Methods (Empty Implementations)

    public func fetchGlobalTotalsByModel() async throws -> [QDBReader.GlobalByModel] {
        // Not implemented for Claude Code
        return []
    }

    public func fetchPeriodTokensByModel(now: Date) async throws -> [QDBReader.PeriodByModel] {
        try await openIfNeeded()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let startOfWeek = now.addingTimeInterval(-7 * 24 * 3600)  // 7 days ago (rolling week)
        let startOfMonth = now.addingTimeInterval(-30 * 24 * 3600)  // 30 days ago (rolling month)
        let startOfYear = calendar.dateInterval(of: .year, for: now)?.start ?? now

        var periodData: [String: QDBReader.PeriodByModel] = [:]

        // Aggregate by model for each time period
        // IMPORTANT: Only count sessions/entries that actually occurred WITHIN each period
        for session in sessions.values {
            let model = session.models.first ?? "claude-3-5-sonnet-20241022"

            // For accurate period costs, we need to filter entries by their timestamps
            // rather than just checking if the session ended after the period start
            var dayTokens = 0
            var weekTokens = 0
            var monthTokens = 0
            var yearTokens = 0
            var dayMessages = 0
            var weekMessages = 0
            var monthMessages = 0
            var dayCost = 0.0
            var weekCost = 0.0
            var monthCost = 0.0
            var yearCost = 0.0

            // Process each entry in the session to properly attribute it to the right period
            for entry in session.entries {
                guard let entryDate = entry.date else { continue }

                let entryTokens = entry.message.usage.totalTokens
                let entryCost: Double
                if let jsonlCost = entry.costUSD, jsonlCost > 0 {
                    entryCost = jsonlCost
                } else {
                    // Calculate cost using ClaudeCostCalculator when JSONL cost is missing
                    let model = entry.message.model ?? "claude-3-5-sonnet-20241022"
                    entryCost = ClaudeCostCalculator.calculateCost(
                        tokens: entry.message.usage,
                        model: model,
                        mode: costMode,
                        existingCost: entry.costUSD
                    )
                }

                // Count this entry in the appropriate periods
                if entryDate >= startOfDay {
                    dayTokens += entryTokens
                    dayMessages += 1
                    dayCost += entryCost
                }
                if entryDate >= startOfWeek {
                    weekTokens += entryTokens
                    weekMessages += 1
                    weekCost += entryCost
                }
                if entryDate >= startOfMonth {
                    monthTokens += entryTokens
                    monthMessages += 1
                    monthCost += entryCost
                }
                if entryDate >= startOfYear {
                    yearTokens += entryTokens
                    yearCost += entryCost
                }
            }

            // Skip if no data for this model in any period
            if yearTokens == 0 { continue }

            // Get current period data or initialize
            var modelData = periodData[model] ?? QDBReader.PeriodByModel(
                modelId: model,
                dayTokens: 0,
                weekTokens: 0,
                monthTokens: 0,
                yearTokens: 0,
                dayMessages: 0,
                weekMessages: 0,
                monthMessages: 0,
                dayCost: 0.0,
                weekCost: 0.0,
                monthCost: 0.0,
                yearCost: 0.0
            )

            // Accumulate the properly filtered data
            modelData = QDBReader.PeriodByModel(
                modelId: model,
                dayTokens: modelData.dayTokens + dayTokens,
                weekTokens: modelData.weekTokens + weekTokens,
                monthTokens: modelData.monthTokens + monthTokens,
                yearTokens: modelData.yearTokens + yearTokens,
                dayMessages: modelData.dayMessages + dayMessages,
                weekMessages: modelData.weekMessages + weekMessages,
                monthMessages: modelData.monthMessages + monthMessages,
                dayCost: modelData.dayCost + dayCost,
                weekCost: modelData.weekCost + weekCost,
                monthCost: modelData.monthCost + monthCost,
                yearCost: modelData.yearCost + yearCost
            )

            // Store the accumulated data
            periodData[model] = modelData
        }

        return Array(periodData.values)
    }

    public func fetchPeriodTokensByModel(
        forKeys keys: [String],
        now: Date
    ) async throws -> [QDBReader.PeriodByModel] {
        // Not implemented for Claude Code
        return []
    }

    public func fetchMonthlyMessageCount(now: Date) async throws -> Int {
        try await openIfNeeded()

        let thirtyDaysAgo = now.addingTimeInterval(-30 * 24 * 3600)  // 30 days ago (rolling month)

        // Count messages from entries in the last 30 days
        var messageCount = 0
        for session in sessions.values {
            for entry in session.entries {
                if let entryDate = entry.date, entryDate >= thirtyDaysAgo {
                    messageCount += 1
                }
            }
        }

        return messageCount
    }

    // MARK: - Private Methods

    /// Get Claude data directories from environment or defaults
    private func getClaudePaths() -> [String] {
        var paths: [String] = []

        // Check environment variable first (comma-separated paths)
        if let envPaths = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            let envPathList = envPaths.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            for envPath in envPathList {
                let expandedPath = NSString(string: envPath).expandingTildeInPath
                let projectsPath = (expandedPath as NSString).appendingPathComponent("projects")
                if FileManager.default.fileExists(atPath: projectsPath) {
                    paths.append(expandedPath)
                }
            }
        }

        // If no valid env paths, use defaults
        if paths.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let defaultPaths = [
                home.appendingPathComponent(".config/claude").path,
                home.appendingPathComponent(".claude").path
            ]

            for defaultPath in defaultPaths {
                let projectsPath = (defaultPath as NSString).appendingPathComponent("projects")
                if FileManager.default.fileExists(atPath: projectsPath) {
                    paths.append(defaultPath)
                }
            }
        }

        return paths
    }

    /// Find all JSONL files in Claude projects directories
    private func findJSONLFiles() -> [URL] {
        let paths = getClaudePaths()
        var jsonlFiles: [URL] = []

        for claudePath in paths {
            let projectsPath = (claudePath as NSString).appendingPathComponent("projects")
            let projectsURL = URL(fileURLWithPath: projectsPath)

            // Find all .jsonl files recursively
            if let enumerator = FileManager.default.enumerator(
                at: projectsURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension == "jsonl" {
                        jsonlFiles.append(fileURL)
                    }
                }
            }
        }

        return jsonlFiles
    }

    /// Load all JSONL files and aggregate into sessions
    private func loadAllData() async throws {
        logger.info("Loading Claude Code usage data")

        let jsonlFiles = findJSONLFiles()
        var allEntries: [ClaudeUsageEntry] = []
        var newModificationTimes: [String: Date] = [:]

        // Parse all JSONL files
        for fileURL in jsonlFiles {
            do {
                let entries = try await parseJSONLFile(at: fileURL)
                allEntries.append(contentsOf: entries)

                // Track modification time
                if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let modDate = attributes[.modificationDate] as? Date {
                    newModificationTimes[fileURL.path] = modDate
                }
            } catch {
                logger.warning("Failed to parse JSONL file at \(fileURL.path): \(error.localizedDescription)")
                // Continue with other files
            }
        }

        // Deduplicate entries
        allEntries = deduplicateEntries(allEntries)

        // Aggregate into sessions
        sessions = aggregateIntoSessions(entries: allEntries)
        lastModificationTimes = newModificationTimes

        logger.info("Loaded \(self.sessions.count) sessions from \(jsonlFiles.count) files")
    }

    /// Parse a single JSONL file
    private func parseJSONLFile(at url: URL) async throws -> [ClaudeUsageEntry] {
        let data = try Data(contentsOf: url)
        let lines = String(data: data, encoding: .utf8)?.components(separatedBy: .newlines) ?? []

        var entries: [ClaudeUsageEntry] = []
        let decoder = JSONDecoder()

        for line in lines {
            guard !line.isEmpty else { continue }

            do {
                let entry = try decoder.decode(ClaudeUsageEntry.self, from: Data(line.utf8))
                entries.append(entry)
            } catch {
                // Skip malformed entries
                logger.debug("Skipping malformed entry: \(error.localizedDescription)")
            }
        }

        return entries
    }

    /// Deduplicate entries using message ID, request ID, and timestamp
    private func deduplicateEntries(_ entries: [ClaudeUsageEntry]) -> [ClaudeUsageEntry] {
        var seen: Set<String> = []
        var deduplicated: [ClaudeUsageEntry] = []

        for entry in entries {
            let key = "\(entry.message.id ?? "")-\(entry.requestId ?? "")-\(entry.timestamp)"
            if !seen.contains(key) {
                seen.insert(key)
                deduplicated.append(entry)
            }
        }

        return deduplicated
    }

    /// Aggregate entries into sessions
    private func aggregateIntoSessions(entries: [ClaudeUsageEntry]) -> [String: ClaudeSession] {
        var sessionMap: [String: ClaudeSession] = [:]

        // Group by sessionId if available, otherwise by cwd + time window
        var entriesBySession: [String: [ClaudeUsageEntry]] = [:]

        for entry in entries {
            // If sessionId exists, use it
            if let sessionId = entry.sessionId, !sessionId.isEmpty {
                entriesBySession[sessionId, default: []].append(entry)
            } else {
                // Group by cwd + 5-hour time windows (Claude's billing blocks)
                let cwd = entry.cwd ?? "unknown"
                if let date = entry.date {
                    // Create a session key based on cwd and 5-hour window
                    let hoursSinceEpoch = Int(date.timeIntervalSince1970 / 3600)
                    let fiveHourBlock = hoursSinceEpoch / 5
                    let sessionKey = "\(cwd)-block\(fiveHourBlock)"
                    entriesBySession[sessionKey, default: []].append(entry)
                } else {
                    // Fallback: create unique session for entries without valid dates
                    let sessionId = "unknown-\(UUID().uuidString)"
                    entriesBySession[sessionId, default: []].append(entry)
                }
            }
        }

        // Create session objects
        for (sessionId, sessionEntries) in entriesBySession {
            let sortedEntries = sessionEntries.sorted { (e1, e2) in
                (e1.date ?? Date.distantPast) < (e2.date ?? Date.distantPast)
            }

            guard !sortedEntries.isEmpty else { continue }

            let startTime = sortedEntries.first?.date ?? Date()
            let endTime = sortedEntries.last?.date ?? Date()

            var totalInputTokens = 0
            var totalOutputTokens = 0
            var totalCacheCreationTokens = 0
            var totalCacheReadTokens = 0
            var totalCost = 0.0
            var totalCostFromJSONL = 0.0
            var models: Set<String> = []
            let cwd = sortedEntries.first(where: { $0.cwd != nil })?.cwd

            for entry in sortedEntries {
                totalInputTokens += entry.message.usage.input_tokens
                totalOutputTokens += entry.message.usage.output_tokens
                totalCacheCreationTokens += entry.message.usage.cache_creation_input_tokens ?? 0
                totalCacheReadTokens += entry.message.usage.cache_read_input_tokens ?? 0

                // Track cost from JSONL separately
                if let jsonlCost = entry.costUSD {
                    totalCostFromJSONL += jsonlCost
                }

                // Calculate cost using the new ClaudeCostCalculator
                let model = entry.message.model ?? "claude-3-5-sonnet-20241022"
                let entryCost = ClaudeCostCalculator.calculateCost(
                    tokens: entry.message.usage,
                    model: model,
                    mode: costMode,
                    existingCost: entry.costUSD
                )
                totalCost += entryCost

                if let model = entry.message.model {
                    models.insert(model)
                }
            }

            sessionMap[sessionId] = ClaudeSession(
                id: sessionId,
                startTime: startTime,
                endTime: endTime,
                entries: sortedEntries,
                totalInputTokens: totalInputTokens,
                totalOutputTokens: totalOutputTokens,
                totalCacheCreationTokens: totalCacheCreationTokens,
                totalCacheReadTokens: totalCacheReadTokens,
                totalCost: totalCost,
                totalCostFromJSONL: totalCostFromJSONL,
                models: models,
                cwd: cwd,
                messageCount: sortedEntries.count
            )
        }

        return sessionMap
    }

    /// Get the default context window for Claude models
    private func getContextWindow(for model: String?) -> Int {
        guard let model = model else { return defaultContextWindow }
        let pricing = ClaudeCostCalculator.getModelPricing(for: model)
        return pricing.maxTokens ?? defaultContextWindow
    }

    /// Check if files have been modified
    private func checkForFileChanges() async -> Int {
        let jsonlFiles = findJSONLFiles()
        var hasChanges = false

        for fileURL in jsonlFiles {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let modDate = attributes[.modificationDate] as? Date {
                if let lastMod = lastModificationTimes[fileURL.path] {
                    if modDate > lastMod {
                        hasChanges = true
                        break
                    }
                } else {
                    // New file
                    hasChanges = true
                    break
                }
            }
        }

        // Also check if files were removed
        if !hasChanges {
            for path in lastModificationTimes.keys {
                if !FileManager.default.fileExists(atPath: path) {
                    hasChanges = true
                    break
                }
            }
        }

        return hasChanges ? dataVersion + 1 : dataVersion
    }

    /// Get session state based on usage percentage
    private func getSessionState(usagePercent: Double) -> SessionState {
        switch usagePercent {
        case 0..<70:
            return .normal
        case 70..<85:
            return .warn
        case 85..<100:
            return .critical
        default:
            return .error
        }
    }
}