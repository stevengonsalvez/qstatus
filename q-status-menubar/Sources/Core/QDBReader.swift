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

public actor QDBReader {
    private let config: QDBConfig
    private var dbPool: DatabasePool?

    // Minimal schema expectations for amazon-q data.sqlite3
    private struct SchemaMap {
        var conversationsTable: String?
        var keyColumn: String?
        var valueColumn: String?
    }
    private var schema = SchemaMap(conversationsTable: "conversations", keyColumn: "key", valueColumn: "value")

    public init(config: QDBConfig = QDBConfig()) {
        self.config = config
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
        var newSchema = self.schema
        try await dbPool.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table'")
            // Heuristics
            newSchema.conversationsTable = tables.first { $0.lowercased() == "conversations" } ?? tables.first { $0.lowercased().contains("conversation") }
            if let ct = newSchema.conversationsTable {
                let cols = try ColumnInfo.fetchAll(db, sql: "PRAGMA table_info(\(rawIdent(ct)))").map { $0.name.lowercased() }
                // conversations(key TEXT PRIMARY KEY, value TEXT)
                newSchema.keyColumn = cols.first { $0 == "key" }
                newSchema.valueColumn = cols.first { $0 == "value" }
            }
        }
        self.schema = newSchema
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
                  LEFT JOIN json_each(p.value,'$.history') AS h
                  ON 1
                  GROUP BY p.key
                )
                SELECT p.key,
                       COALESCE(json_extract(p.value,'$.model_info.context_window_tokens'), 200000) AS ctx_tokens,
                       COALESCE(json_array_length(json_extract(p.value,'$.history')), 0) AS msg_count,
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
                    let ctxTokens: Int = r["ctx_tokens"] ?? 200000
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
                    let usage = ctxTokens > 0 ? min(100.0, max(0.0, (Double(tokens)/Double(ctxTokens))*100.0)) : 0
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
                        let ctx = 200_000
                        let usage = ctx > 0 ? min(100.0, max(0.0, (Double(tokens)/Double(ctx))*100.0)) : 0
                        agg.append(SessionSummary(id: cwd.isEmpty ? "(no-path)" : cwd, cwd: cwd, tokensUsed: tokens, contextWindow: ctx, usagePercent: usage, messageCount: arr.reduce(0){$0+$1.messageCount}, lastActivity: arr.compactMap{$0.lastActivity}.max(), state: usage >= 100 ? .critical : (usage >= 90 ? .warn : .normal), internalRowID: nil, hasCompactionIndicators: arr.contains{ $0.hasCompactionIndicators }, modelId: nil, costUSD: 0.0))
                    }
                    return agg.sorted { ($0.internalRowID ?? 0) > ($1.internalRowID ?? 0) }
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
                    let ctx = est.contextWindow ?? 200_000
                    let usage = ctx > 0 ? min(100.0, max(0.0, (Double(est.tokens)/Double(ctx))*100.0)) : 0
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
                        let ctx = 200_000
                        let usage = ctx > 0 ? min(100.0, max(0.0, (Double(tokens)/Double(ctx))*100.0)) : 0
                        agg.append(SessionSummary(id: cwd.isEmpty ? "(no-path)" : cwd, cwd: cwd, tokensUsed: tokens, contextWindow: ctx, usagePercent: usage, messageCount: arr.reduce(0){$0+$1.messageCount}, lastActivity: arr.compactMap{$0.lastActivity}.max(), state: usage >= 100 ? .critical : (usage >= 90 ? .warn : .normal), internalRowID: nil, hasCompactionIndicators: arr.contains{ $0.hasCompactionIndicators }, modelId: nil, costUSD: 0.0))
                    }
                    return agg.sorted { ($0.internalRowID ?? 0) > ($1.internalRowID ?? 0) }
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
                    let ctx = breakdown.contextWindow ?? 200_000
                    let usage = ctx > 0 ? min(100.0, max(0.0, (Double(breakdown.totalTokens)/Double(ctx))*100.0)) : 0
                    let state: SessionState = usage >= 100 ? .critical : (usage >= 90 ? .warn : .normal)
                    let summary = SessionSummary(id: key, cwd: breakdown.cwd, tokensUsed: breakdown.totalTokens, contextWindow: ctx, usagePercent: usage, messageCount: breakdown.messages, lastActivity: Date(), state: state, internalRowID: rowid, hasCompactionIndicators: breakdown.compactionMarkers, modelId: breakdown.modelId, costUSD: 0.0)
                    return SessionDetails(summary: summary, historyTokens: breakdown.historyTokens, contextFilesTokens: breakdown.contextFilesTokens, toolsTokens: breakdown.toolsTokens, systemTokens: breakdown.systemTokens)
                }
            return nil
        }
    }

    public func sessionCount() async throws -> Int {
        try await openIfNeeded()
        guard let dbPool else { return 0 }
        return try await dbPool.read { db in
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
                    ) >= COALESCE(json_extract(value,'$.model_info.context_window_tokens'),200000) * 0.9
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
                  COALESCE(json_extract(value,'$.model_info.context_window_tokens'),200000) AS ctx
                FROM conversations
                ORDER BY chars DESC
                LIMIT ?;
                """
                let rows = try Row.fetchAll(db, sql: topSQL, arguments: [limitForTop])
                var top: [SessionSummary] = []
                for r in rows {
                    let key: String = r["key"] ?? ""
                    let chars: Int = r["chars"] ?? 0
                    let ctx: Int = r["ctx"] ?? 200000
                    let tokens = Int((((Double(chars)/4.0) + 5.0) / 10.0).rounded(.down) * 10.0)
                    let usage = ctx > 0 ? min(100.0, max(0.0, (Double(tokens)/Double(ctx))*100.0)) : 0.0
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

    // Monthly messages across all sessions (approximate; scans last 30 days of history)
    public func fetchMonthlyMessageCount(now: Date = Date()) async throws -> Int {
        guard await json1Available() else { return 0 }
        try await openIfNeeded()
        guard let dbPool else { return 0 }
        let iso8601 = ISO8601DateFormatter()
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year,.month], from: now)) ?? now
        let since = iso8601.string(from: startOfMonth)
        return try await dbPool.read { db in
            let sql = """
            SELECT COUNT(1) AS cnt
            FROM conversations c, json_each(c.value,'$.history') h
            WHERE COALESCE(
                    json_extract(h.value,'$.assistant.timestamp'),
                    json_extract(h.value,'$.assistant.created_at'),
                    json_extract(h.value,'$.user.timestamp'),
                    json_extract(h.value,'$.user.created_at')
                  ) >= ?
            """
            return try Int.fetchOne(db, sql: sql, arguments: [since]) ?? 0
        }
    }

    public struct PeriodByModel: Sendable {
        public let modelId: String?
        public let dayTokens: Int
        public let weekTokens: Int
        public let monthTokens: Int
        public let dayMessages: Int
        public let weekMessages: Int
        public let monthMessages: Int
    }

    public func fetchPeriodTokensByModel(now: Date = Date()) async throws -> [PeriodByModel] {
        guard await json1Available() else { return [] }
        try await openIfNeeded()
        guard let dbPool else { return [] }
        let iso8601 = ISO8601DateFormatter()
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        let startOfWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear,.weekOfYear], from: now)) ?? startOfDay
        let startOfMonth = cal.date(from: cal.dateComponents([.year,.month], from: now)) ?? startOfDay
        let dayStr = iso8601.string(from: startOfDay)
        let weekStr = iso8601.string(from: startOfWeek)
        let monthStr = iso8601.string(from: startOfMonth)
        return try await dbPool.read { db in
            let sql = """
            WITH hist AS (
              SELECT 
                json_extract(c.value,'$.model_info.model_id') AS model_id,
                COALESCE(
                  json_extract(h.value,'$.assistant.timestamp'),
                  json_extract(h.value,'$.assistant.created_at'),
                  json_extract(h.value,'$.user.timestamp'),
                  json_extract(h.value,'$.user.created_at')
                ) AS ts,
                CAST(((length(h.value)/4.0 + 5.0)/10.0) AS INTEGER)*10 AS tokens
              FROM conversations c, json_each(c.value,'$.history') h
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
            var out: [PeriodByModel] = []
            let rows = try Row.fetchAll(db, sql: sql, arguments: [dayStr, weekStr, monthStr, dayStr, weekStr, monthStr])
            for r in rows {
                let mid: String? = r["model_id"]
                let dTok: Int = r["day_tokens"] ?? 0
                let wTok: Int = r["week_tokens"] ?? 0
                let mTok: Int = r["month_tokens"] ?? 0
                let dMsg: Int = r["day_msgs"] ?? 0
                let wMsg: Int = r["week_msgs"] ?? 0
                let mMsg: Int = r["month_msgs"] ?? 0
                out.append(PeriodByModel(modelId: mid, dayTokens: dTok, weekTokens: wTok, monthTokens: mTok, dayMessages: dMsg, weekMessages: wMsg, monthMessages: mMsg))
            }
            return out
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
              FROM filtered c, json_each(c.value,'$.history') h
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
                out.append(PeriodByModel(modelId: mid, dayTokens: dTok, weekTokens: wTok, monthTokens: mTok, dayMessages: dMsg, weekMessages: wMsg, monthMessages: mMsg))
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
