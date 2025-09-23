import Foundation
import GRDB

public struct QDBConfig: Sendable {
    public var dbPath: String
    public init(dbPath: String = QDBConfig.defaultDBPath()) {
        self.dbPath = dbPath
    }

    public static func defaultDBPath() -> String {
        // Env override first
        if let env = ProcessInfo.processInfo.environment["QSTATUS_DB_PATH"], !env.isEmpty {
            return (env as NSString).expandingTildeInPath
        }
        // macOS default per research: ~/Library/Application Support/amazon-q/data.sqlite3
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent("Library/Application Support/amazon-q/data.sqlite3")
        return url.path
    }
}

public actor QDBReader: DataSource {
    private let config: QDBConfig
    private var dbPool: DatabasePool?
    private let defaultContextWindow: Int
    // History table exists but is never populated by Q CLI - removed usage

    // Minimal schema expectations for amazon-q data.sqlite3
    private struct SchemaMap {
        var conversationsTable: String?
        var keyColumn: String?
        var valueColumn: String?
    }
    private var schema = SchemaMap(conversationsTable: "conversations", keyColumn: "key", valueColumn: "value")

    public init(config: QDBConfig = QDBConfig(), defaultContextWindow: Int = 175_000) {
        self.config = config
        self.defaultContextWindow = defaultContextWindow
    }

    public func openIfNeeded() async throws {
        if dbPool != nil { return }
        var configuration = Configuration()
        configuration.readonly = true
        configuration.busyMode = .timeout(0) // fail fast; readers shouldn't block writers in WAL
        configuration.maximumReaderCount = 4
        let url = URL(fileURLWithPath: config.dbPath)
        dbPool = try DatabasePool(path: url.path, configuration: configuration)
        try await discoverSchema()
    }

    private func discoverSchema() async throws {
        guard let dbPool else { return }
        let schemaOut = try await dbPool.read { db -> SchemaMap in
            var newSchema = SchemaMap(conversationsTable: nil, keyColumn: nil, valueColumn: nil)
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table'")
            // Heuristics
            newSchema.conversationsTable = tables.first { $0.lowercased() == "conversations" } ?? tables.first { $0.lowercased().contains("conversation") }
            if let ct = newSchema.conversationsTable {
                let cols = try ColumnInfo.fetchAll(db, sql: "PRAGMA table_info(\(rawIdent(ct)))").map { $0.name.lowercased() }
                // conversations(key TEXT PRIMARY KEY, value TEXT)
                newSchema.keyColumn = cols.first { $0 == "key" }
                newSchema.valueColumn = cols.first { $0 == "value" }
            }
            return newSchema
        }
        var finalSchema = schemaOut
        if finalSchema.conversationsTable == nil { finalSchema.conversationsTable = "conversations" }
        if finalSchema.keyColumn == nil { finalSchema.keyColumn = "key" }
        if finalSchema.valueColumn == nil { finalSchema.valueColumn = "value" }
        self.schema = finalSchema
        // History table not used
    }

    public func dataVersion() async throws -> Int {
        try await openIfNeeded()
        guard let dbPool else { return 0 }
        return try await dbPool.read { db in
            let val = try Int.fetchOne(db, sql: "PRAGMA data_version;") ?? 0
            return val
        }
    }

    public func fetchLatestUsage(window: TimeInterval? = nil) async throws -> UsageSnapshot {
        try await openIfNeeded()
        guard let dbPool else { throw NSError(domain: "QDBReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "DB not open"]) }

        let s = self.schema
        return try await dbPool.read { db in
            let now = Date()
            guard let ct = s.conversationsTable, let keyCol = s.keyColumn, let valueCol = s.valueColumn else {
                return UsageSnapshot(timestamp: now, tokensUsed: 0, messageCount: 0, conversationId: nil, sessionLimitOverride: nil)
            }

            // Latest conversation by rowid (most recently inserted/updated)
            let row = try Row.fetchOne(db, sql: "SELECT rowid, \(rawIdent(keyCol)) AS k, \(rawIdent(valueCol)) AS v FROM \(rawIdent(ct)) ORDER BY rowid DESC LIMIT 1")
            let convId: String? = row?["k"]
            let convJSON: String? = row?["v"]

            var tokens = 0
            var msgCount = 0
            var sessionLimit: Int? = nil
            if let json = convJSON {
                let result = estimateTokensAndMessages(fromJSONString: json)
                tokens = result.tokens
                msgCount = result.messages
                sessionLimit = result.contextWindowTokens
            }

            return UsageSnapshot(timestamp: now, tokensUsed: tokens, messageCount: msgCount, conversationId: convId, sessionLimitOverride: sessionLimit)
        }
    }

    // MARK: - JSON1 availability

    public func json1Available() async -> Bool {
        do {
            try await openIfNeeded()
            guard let dbPool else { return false }
            return try await dbPool.read { db in
                do {
                    _ = try String.fetchOne(db, sql: "SELECT json_extract('{\"a\":1}','$.a')")
                    return true
                } catch {
                    return false
                }
            }
        } catch { return false }
    }

    // MARK: - Sessions enumeration

    public func fetchSessions(limit: Int = 50, offset: Int = 0, groupByFolder: Bool = false, activeOnly: Bool = false) async throws -> [SessionSummary] {
        try await openIfNeeded()
        guard let dbPool else { return [] }

        let supportsJSON1 = await json1Available()
        let now = Date()

        // Always use conversations table (history table is never populated)
        if supportsJSON1 {
            return try await dbPool.read { db in
                // Limit first, then expand last_ts via json_each only for the page subset
                let sql = """
                WITH page AS (
                  SELECT key, value, rowid AS internal_rowid
                  FROM conversations
                  ORDER BY rowid DESC
                  LIMIT ? OFFSET ?
                ), last AS (
                  SELECT p.key AS key,
                         MAX(
                           COALESCE(
                             json_extract(h.value,'$.assistant.timestamp'),
                             json_extract(h.value,'$.assistant.created_at'),
                             json_extract(h.value,'$.user.timestamp'),
                             json_extract(h.value,'$.user.created_at')
                           )
                         ) AS last_ts
                  FROM page p
                  LEFT JOIN json_each(CASE 
                    WHEN json_type(json_extract(p.value,'$.history')) = 'array' 
                    THEN json_extract(p.value,'$.history')
                    ELSE '[]'
                  END) AS h
                  ON 1
                  GROUP BY p.key
                )
                SELECT p.key,
                       COALESCE(json_extract(p.value,'$.model_info.context_window_tokens'), \(self.defaultContextWindow)) AS ctx_tokens,
                       CASE 
                         WHEN json_type(json_extract(p.value,'$.history')) = 'array' 
                         THEN COALESCE(json_array_length(json_extract(p.value,'$.history')), 0)
                         WHEN json_type(json_extract(p.value,'$.history')) = 'object'
                         THEN COALESCE(json_array_length(json_extract(p.value,'$.history'), '$'), 0)
                         ELSE 0
                       END AS msg_count,
                       json_extract(p.value,'$.env_context.env_state.current_working_directory') AS cwd,
                       json_extract(p.value,'$.model_info.model_id') AS model_id,
                       COALESCE(length(json_extract(p.value,'$.history')), 0) AS history_chars,
                       COALESCE(length(json_extract(p.value,'$.context_manager.context_files')), 0) AS ctxfiles_chars,
                       COALESCE(length(json_extract(p.value,'$.tool_manager')), 0) AS tools_chars,
                       COALESCE(length(json_extract(p.value,'$.system_prompts')), 0) AS sys_chars,
                       COALESCE(length(p.value), 0) AS value_chars,
                       p.internal_rowid,
                       l.last_ts
                FROM page p
                LEFT JOIN last l ON l.key = p.key
                ORDER BY p.internal_rowid DESC;
                """
                var results: [SessionSummary] = []
                let rows = try Row.fetchAll(db, sql: sql, arguments: [limit, offset])
                for r in rows {
                    let key: String = r["key"] ?? ""
                    let ctxTokens: Int = r["ctx_tokens"] ?? self.defaultContextWindow
                    let msgCount: Int = r["msg_count"] ?? 0
                    let cwd: String? = r["cwd"]
                    let modelId: String? = r["model_id"]
                    let historyChars: Int = r["history_chars"] ?? 0
                    let ctxFilesChars: Int = r["ctxfiles_chars"] ?? 0
                    let toolsChars: Int = r["tools_chars"] ?? 0
                    let sysChars: Int = r["sys_chars"] ?? 0
                    let fallbackChars: Int = r["value_chars"] ?? 0
                    let lastTS: String? = r["last_ts"]
                    let lastDate: Date? = ISO8601DateFormatter().date(from: lastTS ?? "")

                    let breakdown = TokenEstimator.Breakdown(historyChars: historyChars,
                                                             contextFilesChars: ctxFilesChars,
                                                             toolsChars: toolsChars,
                                                             systemChars: sysChars,
                                                             fallbackChars: fallbackChars)
                    let tokens = TokenEstimator.estimateTokens(breakdown: breakdown)
                    // Cap at 99.9% unless truly at or above limit
                    let rawUsage = ctxTokens > 0 ? (Double(tokens)/Double(ctxTokens))*100.0 : 0
                    let usage = tokens >= ctxTokens ? 100.0 : min(99.9, max(0.0, rawUsage))
                    let state: SessionState = usage >= 100 ? .critical : (usage >= 90 ? .warn : .normal)
                    let rowid: Int64? = r["internal_rowid"]
                    results.append(SessionSummary(id: key, cwd: cwd, tokensUsed: tokens, contextWindow: ctxTokens, usagePercent: usage, messageCount: msgCount, lastActivity: lastDate ?? now, state: state, internalRowID: rowid, hasCompactionIndicators: false, modelId: modelId, costUSD: 0.0))
                }
                // Active filter in Swift
                let filtered = activeOnly ? results.filter { ($0.lastActivity ?? now) >= now.addingTimeInterval(-7*24*3600) } : results
                if groupByFolder {
                    // Aggregate by cwd
                    let grouped = Dictionary(grouping: filtered, by: { $0.cwd ?? "" })
                    var agg: [SessionSummary] = []
                    for (cwd, arr) in grouped {
                        let tokens = arr.reduce(0) { $0 + $1.tokensUsed }
                        let ctx = self.defaultContextWindow
                        // Cap at 99.9% unless truly at or above limit
                        let rawUsage = ctx > 0 ? (Double(tokens)/Double(ctx))*100.0 : 0
                        let usage = tokens >= ctx ? 100.0 : min(99.9, max(0.0, rawUsage))
                        agg.append(SessionSummary(id: cwd.isEmpty ? "(no-path)" : cwd, cwd: cwd, tokensUsed: tokens, contextWindow: ctx, usagePercent: usage, messageCount: arr.reduce(0){$0+$1.messageCount}, lastActivity: arr.compactMap{$0.lastActivity}.max(), state: usage >= 100 ? .critical : (usage >= 90 ? .warn : .normal), internalRowID: nil, hasCompactionIndicators: arr.contains{ $0.hasCompactionIndicators }, modelId: nil, costUSD: 0.0))
                    }
                    // Sort grouped sessions by last activity or tokens since internalRowID is nil for groups
                    return agg.sorted { 
                        if let a = $0.lastActivity, let b = $1.lastActivity {
                            return a > b
                        }
                        return $0.tokensUsed > $1.tokensUsed
                    }
                }
                return filtered
            }
        } else {
            // Fallback: fetch key/value and estimate in Swift for the page
            return try await dbPool.read { db in
                let sql = "SELECT key, value FROM conversations ORDER BY rowid DESC LIMIT ? OFFSET ?;"
                var results: [SessionSummary] = []
                let rows = try Row.fetchAll(db, sql: sql, arguments: [limit, offset])
                for r in rows {
                    guard let key: String = r["key"], let value: String = r["value"] else { continue }
                    let est = TokenEstimator.estimate(from: value)
                    let ctx = est.contextWindow ?? self.defaultContextWindow
                    // Cap at 99.9% unless truly at or above limit
                    let rawUsage = ctx > 0 ? (Double(est.tokens)/Double(ctx))*100.0 : 0
                    let usage = est.tokens >= ctx ? 100.0 : min(99.9, max(0.0, rawUsage))
                    let state: SessionState = usage >= 100 ? .critical : (usage >= 90 ? .warn : .normal)
                    let lastDate: Date? = nil // unknown in fallback
                    results.append(SessionSummary(id: key, cwd: est.cwd, tokensUsed: est.tokens, contextWindow: ctx, usagePercent: usage, messageCount: est.messages, lastActivity: lastDate ?? now, state: state, internalRowID: nil, hasCompactionIndicators: false, modelId: est.modelId, costUSD: 0.0))
                }
                let filtered = activeOnly ? results.filter { ($0.lastActivity ?? now) >= now.addingTimeInterval(-7*24*3600) } : results
                if groupByFolder {
                    let grouped = Dictionary(grouping: filtered, by: { $0.cwd ?? "" })
                    var agg: [SessionSummary] = []
                    for (cwd, arr) in grouped {
                        let tokens = arr.reduce(0) { $0 + $1.tokensUsed }
                        let ctx = self.defaultContextWindow
                        // Cap at 99.9% unless truly at or above limit
                        let rawUsage = ctx > 0 ? (Double(tokens)/Double(ctx))*100.0 : 0
                        let usage = tokens >= ctx ? 100.0 : min(99.9, max(0.0, rawUsage))
                        agg.append(SessionSummary(id: cwd.isEmpty ? "(no-path)" : cwd, cwd: cwd, tokensUsed: tokens, contextWindow: ctx, usagePercent: usage, messageCount: arr.reduce(0){$0+$1.messageCount}, lastActivity: arr.compactMap{$0.lastActivity}.max(), state: usage >= 100 ? .critical : (usage >= 90 ? .warn : .normal), internalRowID: nil, hasCompactionIndicators: arr.contains{ $0.hasCompactionIndicators }, modelId: nil, costUSD: 0.0))
                    }
                    // Sort grouped sessions by last activity or tokens since internalRowID is nil for groups
                    return agg.sorted { 
                        if let a = $0.lastActivity, let b = $1.lastActivity {
                            return a > b
                        }
                        return $0.tokensUsed > $1.tokensUsed
                    }
                }
                return filtered
            }
        }
    }

    public func fetchSessionDetail(key: String) async throws -> SessionDetails? {
        try await openIfNeeded()
        guard let dbPool else { return nil }
        return try await dbPool.read { db in
                if let row = try Row.fetchOne(db, sql: "SELECT value, rowid FROM conversations WHERE key = ?", arguments: [key]) {
                    let value: String? = row["value"]
                    let rowid: Int64? = row["rowid"]
                    guard let json = value else { return nil }
                    let breakdown = TokenEstimator.estimateBreakdown(from: json)
                    let ctx = breakdown.contextWindow ?? self.defaultContextWindow
                    // Cap at 99.9% unless truly at or above limit
                    let rawUsage = ctx > 0 ? (Double(breakdown.totalTokens)/Double(ctx))*100.0 : 0
                    let usage = breakdown.totalTokens >= ctx ? 100.0 : min(99.9, max(0.0, rawUsage))
                    let state: SessionState = usage >= 100 ? .critical : (usage >= 90 ? .warn : .normal)
                    let summary = SessionSummary(id: key, cwd: breakdown.cwd, tokensUsed: breakdown.totalTokens, contextWindow: ctx, usagePercent: usage, messageCount: breakdown.messages, lastActivity: Date(), state: state, internalRowID: rowid, hasCompactionIndicators: breakdown.compactionMarkers, modelId: breakdown.modelId, costUSD: 0.0)
                    return SessionDetails(summary: summary, historyTokens: breakdown.historyTokens, contextFilesTokens: breakdown.contextFilesTokens, toolsTokens: breakdown.toolsTokens, systemTokens: breakdown.systemTokens)
                }
            return nil
        }
    }

    public func sessionCount(activeOnly: Bool = false) async throws -> Int {
        try await openIfNeeded()
        guard let dbPool else { return 0 }
        // Always use conversations table (history table is never populated)
        return try await dbPool.read { db in
            // For now, activeOnly filter would need JSON parsing of timestamps
            // Since history table is unused, we can't filter by activity time reliably
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM conversations") ?? 0
        }
    }

    public func fetchGlobalMetrics(limitForTop: Int = 5) async throws -> GlobalMetrics {
        try await openIfNeeded()
        guard let dbPool else { return GlobalMetrics(totalSessions: 0, totalTokens: 0, sessionsNearLimit: 0, topHeavySessions: []) }
        if await json1Available() {
            return try await dbPool.read { db in
                // Global aggregates
                let aggSQL = """
                SELECT 
                  COUNT(*) AS total_sessions,
                  SUM(
                    CASE WHEN (
                      COALESCE(length(json_extract(value,'$.history')),0) +
                      COALESCE(length(json_extract(value,'$.context_manager.context_files')),0) +
                      COALESCE(length(json_extract(value,'$.tool_manager')),0) +
                      COALESCE(length(json_extract(value,'$.system_prompts')),0)
                    ) > 0 THEN (
                      COALESCE(length(json_extract(value,'$.history')),0) +
                      COALESCE(length(json_extract(value,'$.context_manager.context_files')),0) +
                      COALESCE(length(json_extract(value,'$.tool_manager')),0) +
                      COALESCE(length(json_extract(value,'$.system_prompts')),0)
                    ) ELSE length(value) END
                  ) AS total_chars,
                  SUM(
                    CASE WHEN (
                      (CASE WHEN (
                        COALESCE(length(json_extract(value,'$.history')),0) +
                        COALESCE(length(json_extract(value,'$.context_manager.context_files')),0) +
                        COALESCE(length(json_extract(value,'$.tool_manager')),0) +
                        COALESCE(length(json_extract(value,'$.system_prompts')),0)
                      ) > 0 THEN (
                        COALESCE(length(json_extract(value,'$.history')),0) +
                        COALESCE(length(json_extract(value,'$.context_manager.context_files')),0) +
                        COALESCE(length(json_extract(value,'$.tool_manager')),0) +
                        COALESCE(length(json_extract(value,'$.system_prompts')),0)
                      ) ELSE length(value) END) / 4.0
                    ) >= COALESCE(json_extract(value,'$.model_info.context_window_tokens'),\(self.defaultContextWindow)) * 0.9
                    THEN 1 ELSE 0 END
                  ) AS near_count
                FROM conversations;
                """
                let agg = try Row.fetchOne(db, sql: aggSQL)
                let totalSessions: Int = agg?["total_sessions"] ?? 0
                let totalChars: Int = agg?["total_chars"] ?? 0
                let nearCount: Int = agg?["near_count"] ?? 0
                let totalTokens = Int((((Double(totalChars)/4.0) + 5.0) / 10.0).rounded(.down) * 10.0)

                // Top heavy sessions by estimated tokens
                let topSQL = """
                SELECT key,
                  (CASE WHEN (
                    COALESCE(length(json_extract(value,'$.history')),0) +
                    COALESCE(length(json_extract(value,'$.context_manager.context_files')),0) +
                    COALESCE(length(json_extract(value,'$.tool_manager')),0) +
                    COALESCE(length(json_extract(value,'$.system_prompts')),0)
                  ) > 0 THEN (
                    COALESCE(length(json_extract(value,'$.history')),0) +
                    COALESCE(length(json_extract(value,'$.context_manager.context_files')),0) +
                    COALESCE(length(json_extract(value,'$.tool_manager')),0) +
                    COALESCE(length(json_extract(value,'$.system_prompts')),0)
                  ) ELSE length(value) END) AS chars,
                  COALESCE(json_extract(value,'$.model_info.context_window_tokens'),\(self.defaultContextWindow)) AS ctx
                FROM conversations
                ORDER BY chars DESC
                LIMIT ?;
                """
                let rows = try Row.fetchAll(db, sql: topSQL, arguments: [limitForTop])
                var top: [SessionSummary] = []
                for r in rows {
                    let key: String = r["key"] ?? ""
                    let chars: Int = r["chars"] ?? 0
                    let ctx: Int = r["ctx"] ?? self.defaultContextWindow
                    let tokens = Int((((Double(chars)/4.0) + 5.0) / 10.0).rounded(.down) * 10.0)
                    // Cap at 99.9% unless truly at or above limit
                    let rawUsage = ctx > 0 ? (Double(tokens)/Double(ctx))*100.0 : 0.0
                    let usage = tokens >= ctx ? 100.0 : min(99.9, max(0.0, rawUsage))
                    let state: SessionState = usage >= 100 ? .critical : (usage >= 90 ? .warn : .normal)
                    top.append(SessionSummary(id: key, cwd: nil, tokensUsed: tokens, contextWindow: ctx, usagePercent: usage, messageCount: 0, lastActivity: nil, state: state, internalRowID: nil, hasCompactionIndicators: false, modelId: nil, costUSD: 0.0))
                }
                return GlobalMetrics(totalSessions: totalSessions, totalTokens: totalTokens, sessionsNearLimit: nearCount, topHeavySessions: top)
            }
        } else {
            // Fallback: approximate with SUM(length(value))/4 for tokens, count(*), no near-limit breakdown
            return try await dbPool.read { db in
                let totalSessions = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM conversations") ?? 0
                let totalChars = try Int.fetchOne(db, sql: "SELECT SUM(length(value)) FROM conversations") ?? 0
                let totalTokens = Int((((Double(totalChars)/4.0) + 5.0) / 10.0).rounded(.down) * 10.0)
                return GlobalMetrics(totalSessions: totalSessions, totalTokens: totalTokens, sessionsNearLimit: 0, topHeavySessions: [])
            }
        }
    }

    // Precise global totals grouped by model using per-category rounding to nearest 10, then summed.
    public struct GlobalByModel: Sendable { public let modelId: String?; public let tokens: Int; public let messages: Int }
    public func fetchGlobalTotalsByModel() async throws -> [GlobalByModel] {
        guard await json1Available() else { return [] }
        try await openIfNeeded()
        guard let dbPool else { return [] }
        let sql = """
        WITH per_conv AS (
          SELECT 
            json_extract(value,'$.model_info.model_id') AS model_id,
            CASE 
              WHEN json_type(json_extract(value,'$.history')) = 'array' 
              THEN COALESCE(json_array_length(json_extract(value,'$.history')), 0)
              WHEN json_type(json_extract(value,'$.history')) = 'object'
              THEN COALESCE(json_array_length(json_extract(value,'$.history'), '$'), 0)
              ELSE 0
            END AS msgs,
            CASE WHEN (
              COALESCE(length(json_extract(value,'$.history')),0) +
              COALESCE(length(json_extract(value,'$.context_manager.context_files')),0) +
              COALESCE(length(json_extract(value,'$.tool_manager')),0) +
              COALESCE(length(json_extract(value,'$.system_prompts')),0)
            ) > 0 THEN (
              CAST(((length(json_extract(value,'$.history'))/4.0 + 5.0)/10.0) AS INTEGER)*10 +
              CAST(((length(json_extract(value,'$.context_manager.context_files'))/4.0 + 5.0)/10.0) AS INTEGER)*10 +
              CAST(((length(json_extract(value,'$.tool_manager'))/4.0 + 5.0)/10.0) AS INTEGER)*10 +
              CAST(((length(json_extract(value,'$.system_prompts'))/4.0 + 5.0)/10.0) AS INTEGER)*10
            ) ELSE CAST(((length(value)/4.0 + 5.0)/10.0) AS INTEGER)*10 END AS tokens
          FROM conversations
        )
        SELECT model_id, SUM(tokens) AS tokens, SUM(msgs) AS messages
        FROM per_conv
        GROUP BY model_id;
        """
        return try await dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: sql)
            var out: [GlobalByModel] = []
            for r in rows {
                let mid: String? = r["model_id"]
                let t: Int = r["tokens"] ?? 0
                let m: Int = r["messages"] ?? 0
                out.append(GlobalByModel(modelId: mid, tokens: t, messages: m))
            }
            return out
        }
    }

    // Monthly messages across all sessions.
    // History table is never populated, so we estimate from conversations table
    public func fetchMonthlyMessageCount(now: Date = Date()) async throws -> Int {
        try await openIfNeeded()
        guard let dbPool else { return 0 }
        
        // Since history table is unused, estimate monthly messages from conversations
        // This counts total messages in all conversations (not ideal but better than 0)
        let supportsJSON1 = await json1Available()
        if supportsJSON1 {
            return try await dbPool.read { db in
                // Sum up message counts from all conversations, handling both array and object types
                let sql = """
                SELECT SUM(
                  CASE 
                    WHEN json_type(json_extract(value,'$.history')) = 'array' 
                    THEN COALESCE(json_array_length(json_extract(value,'$.history')), 0)
                    WHEN json_type(json_extract(value,'$.history')) = 'object'
                    THEN COALESCE(json_array_length(json_extract(value,'$.history'), '$'), 0)
                    ELSE 0
                  END
                ) 
                FROM conversations
                """
                return try Int.fetchOne(db, sql: sql) ?? 0
            }
        }
        // Fallback: estimate based on conversation count
        return try await dbPool.read { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM conversations") ?? 0
            // Rough estimate: assume 20 messages per conversation on average
            return count * 20
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

        // Backward compatibility initializer without cost fields
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

        // Full initializer with cost fields
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

    public func fetchPeriodTokensByModel(now: Date = Date()) async throws -> [PeriodByModel] {
        guard await json1Available() else { return [] }
        try await openIfNeeded()
        guard let dbPool else { return [] }
        // Use history to select directories active in each period; sum current conversation tokens by model
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        let startOfWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear,.weekOfYear], from: now)) ?? startOfDay
        let startOfMonth = cal.date(from: cal.dateComponents([.year,.month], from: now)) ?? startOfDay
        let startOfYear = cal.date(from: cal.dateComponents([.year], from: now)) ?? startOfDay
        let dayEpoch = Int64(startOfDay.timeIntervalSince1970)
        let weekEpoch = Int64(startOfWeek.timeIntervalSince1970)
        let monthEpoch = Int64(startOfMonth.timeIntervalSince1970)
        let yearEpoch = Int64(startOfYear.timeIntervalSince1970)
        guard let ct = schema.conversationsTable, let keyCol = schema.keyColumn, let valueCol = schema.valueColumn else { return [] }
        return try await dbPool.read { db in
            // Precompute per-dir tokens + model from conversations
            let convSQL = """
            SELECT 
              \(rawIdent(keyCol)) AS cwd,
              COALESCE(json_extract(\(rawIdent(valueCol)),'$.model_info.model_id'), NULL) AS model_id,
              COALESCE(length(json_extract(\(rawIdent(valueCol)),'$.history')),0) AS h_chars,
              COALESCE(length(json_extract(\(rawIdent(valueCol)),'$.context_manager.context_files')),0) AS ctx_chars,
              COALESCE(length(json_extract(\(rawIdent(valueCol)),'$.tool_manager')),0) AS tools_chars,
              COALESCE(length(json_extract(\(rawIdent(valueCol)),'$.system_prompts')),0) AS sys_chars,
              COALESCE(length(\(rawIdent(valueCol))),0) AS fallback_chars
            FROM \(rawIdent(ct));
            """
            let convRows = try Row.fetchAll(db, sql: convSQL)
            var dirTokens: [String: (model: String?, tokens: Int)] = [:]
            for r in convRows {
                let cwd: String = r["cwd"] ?? ""
                let mid: String? = r["model_id"]
                let h: Int = r["h_chars"] ?? 0
                let cx: Int = r["ctx_chars"] ?? 0
                let tl: Int = r["tools_chars"] ?? 0
                let sy: Int = r["sys_chars"] ?? 0
                let fb: Int = r["fallback_chars"] ?? 0
                let br = TokenEstimator.Breakdown(historyChars: h, contextFilesChars: cx, toolsChars: tl, systemChars: sy, fallbackChars: fb)
                dirTokens[cwd] = (mid, TokenEstimator.estimateTokens(breakdown: br))
            }
            // Since history table is unused, consider all directories as potentially active
            // In a real implementation, we'd need to track session timestamps differently
            let allDirs = Set(dirTokens.keys)
            let dDirs = allDirs  // All conversations considered for daily
            let wDirs = allDirs  // All conversations considered for weekly  
            let mDirs = allDirs  // All conversations considered for monthly
            let yDirs = allDirs  // All conversations considered for yearly

            // Aggregate by model
            var byModel: [String?: (d:Int,w:Int,m:Int,y:Int, dm:Int, wm:Int, mm:Int)] = [:]
            func add(model: String?, tokens: Int, to set: String) {
                var rec = byModel[model] ?? (0,0,0,0,0,0,0)
                switch set {
                case "d": rec.0 += tokens; rec.4 += 1
                case "w": rec.1 += tokens; rec.5 += 1
                case "m": rec.2 += tokens; rec.6 += 1
                case "y": rec.3 += tokens
                default: break
                }
                byModel[model] = rec
            }
            for (cwd, val) in dirTokens {
                if dDirs.contains(cwd) { add(model: val.model, tokens: val.tokens, to: "d") }
                if wDirs.contains(cwd) { add(model: val.model, tokens: val.tokens, to: "w") }
                if mDirs.contains(cwd) { add(model: val.model, tokens: val.tokens, to: "m") }
                if yDirs.contains(cwd) { add(model: val.model, tokens: val.tokens, to: "y") }
            }
            // Calculate costs using default rate (this will be overridden by settings in UpdateCoordinator)
            let defaultRate = 0.0025 // Default rate per 1k tokens
            return byModel.map { (k,v) in
                let dayCost = CostEstimator.estimateUSD(tokens: v.0, ratePer1k: defaultRate)
                let weekCost = CostEstimator.estimateUSD(tokens: v.1, ratePer1k: defaultRate)
                let monthCost = CostEstimator.estimateUSD(tokens: v.2, ratePer1k: defaultRate)
                let yearCost = CostEstimator.estimateUSD(tokens: v.3, ratePer1k: defaultRate)
                return PeriodByModel(
                    modelId: k,
                    dayTokens: v.0, weekTokens: v.1, monthTokens: v.2, yearTokens: v.3,
                    dayMessages: v.4, weekMessages: v.5, monthMessages: v.6,
                    dayCost: dayCost, weekCost: weekCost, monthCost: monthCost, yearCost: yearCost
                )
            }
        }
    }

    public func fetchPeriodTokensByModel(forKeys keys: [String], now: Date = Date()) async throws -> [PeriodByModel] {
        guard await json1Available() else { return [] }
        try await openIfNeeded()
        guard let dbPool, !keys.isEmpty else { return [] }
        let iso8601 = ISO8601DateFormatter()
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        let startOfWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear,.weekOfYear], from: now)) ?? startOfDay
        let startOfMonth = cal.date(from: cal.dateComponents([.year,.month], from: now)) ?? startOfDay
        let dayStr = iso8601.string(from: startOfDay)
        let weekStr = iso8601.string(from: startOfWeek)
        let monthStr = iso8601.string(from: startOfMonth)
        return try await dbPool.read { db in
            // Build placeholders for IN clause
            let placeholders = Array(repeating: "?", count: keys.count).joined(separator: ",")
            let sql = """
            WITH filtered AS (
              SELECT * FROM conversations WHERE key IN (
                \(placeholders)
              )
            ), hist AS (
              SELECT 
                json_extract(c.value,'$.model_info.model_id') AS model_id,
                COALESCE(
                  json_extract(h.value,'$.assistant.timestamp'),
                  json_extract(h.value,'$.assistant.created_at'),
                  json_extract(h.value,'$.user.timestamp'),
                  json_extract(h.value,'$.user.created_at')
                ) AS ts,
                CAST(((length(h.value)/4.0 + 5.0)/10.0) AS INTEGER)*10 AS tokens
              FROM filtered c, json_each(
                CASE 
                  WHEN json_type(json_extract(c.value,'$.history')) = 'array' 
                  THEN json_extract(c.value,'$.history')
                  ELSE '[]'
                END
              ) h
            )
            SELECT model_id,
              SUM(CASE WHEN ts >= ? THEN tokens ELSE 0 END) AS day_tokens,
              SUM(CASE WHEN ts >= ? THEN tokens ELSE 0 END) AS week_tokens,
              SUM(CASE WHEN ts >= ? THEN tokens ELSE 0 END) AS month_tokens,
              SUM(CASE WHEN ts >= ? THEN 1 ELSE 0 END) AS day_msgs,
              SUM(CASE WHEN ts >= ? THEN 1 ELSE 0 END) AS week_msgs,
              SUM(CASE WHEN ts >= ? THEN 1 ELSE 0 END) AS month_msgs
            FROM hist
            WHERE ts IS NOT NULL
            GROUP BY model_id;
            """
            var args: [DatabaseValueConvertible] = keys
            args.append(contentsOf: [dayStr, weekStr, monthStr, dayStr, weekStr, monthStr])
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            var out: [PeriodByModel] = []
            for r in rows {
                let mid: String? = r["model_id"]
                let dTok: Int = r["day_tokens"] ?? 0
                let wTok: Int = r["week_tokens"] ?? 0
                let mTok: Int = r["month_tokens"] ?? 0
                let dMsg: Int = r["day_msgs"] ?? 0
                let wMsg: Int = r["week_msgs"] ?? 0
                let mMsg: Int = r["month_msgs"] ?? 0
                // Calculate costs using default rate (this will be overridden by settings in UpdateCoordinator)
                let defaultRate = 0.0025 // Default rate per 1k tokens
                let dayCost = CostEstimator.estimateUSD(tokens: dTok, ratePer1k: defaultRate)
                let weekCost = CostEstimator.estimateUSD(tokens: wTok, ratePer1k: defaultRate)
                let monthCost = CostEstimator.estimateUSD(tokens: mTok, ratePer1k: defaultRate)
                let yearCost = 0.0 // Year tokens not calculated in this method
                out.append(PeriodByModel(
                    modelId: mid,
                    dayTokens: dTok, weekTokens: wTok, monthTokens: mTok, yearTokens: 0,
                    dayMessages: dMsg, weekMessages: wMsg, monthMessages: mMsg,
                    dayCost: dayCost, weekCost: weekCost, monthCost: monthCost, yearCost: yearCost
                ))
            }
            return out
        }
    }
}

private struct ColumnInfo: FetchableRecord, Decodable { let cid: Int; let name: String; let type: String?; let notnull: Int; let dflt_value: String?; let pk: Int }
// Simple identifier quoting for PRAGMA/SQL snippets where parameter binding is unavailable.
private func rawIdent(_ name: String) -> String {
    // Quote using double quotes for identifiers; escape internal quotes
    let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
    return "\"\(escaped)\""
}

// MARK: - Token Estimation from JSON

private func estimateTokensAndMessages(fromJSONString text: String) -> (tokens: Int, messages: Int, contextWindowTokens: Int?) {
    // Rough token estimate: ~4 chars per token
    let charsPerToken = 4.0
    var totalChars = 0
    var messages = 0
    var contextWindow: Int? = nil

    guard let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        // fallback to raw length
        totalChars = text.count
        return (Int(Double(totalChars) / charsPerToken), messages, contextWindow)
    }

    if let modelInfo = json["model_info"] as? [String: Any], let cw = modelInfo["context_window_tokens"] as? Int { contextWindow = cw }

    if let history = json["history"] as? [Any] {
        messages = history.count
        for item in history {
            totalChars += deepStringCharacterCount(item)
        }
    } else {
        totalChars += deepStringCharacterCount(json)
    }

    let tokens = Int((Double(totalChars) / charsPerToken).rounded())
    return (tokens, messages, contextWindow)
}

private func deepStringCharacterCount(_ any: Any) -> Int {
    if let s = any as? String { return s.count }
    if let d = any as? [String: Any] { return d.values.reduce(0) { $0 + deepStringCharacterCount($1) } }
    if let a = any as? [Any] { return a.reduce(0) { $0 + deepStringCharacterCount($1) } }
    return 0
}
