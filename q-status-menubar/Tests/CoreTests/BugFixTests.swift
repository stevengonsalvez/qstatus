import Testing
import GRDB
@testable import Core
import Foundation

// MARK: - Test helpers: in-memory QDBReader with seeded data

private func makeTestDB(conversations: [(key: String, json: String)]) throws -> String {
    let tmp = NSTemporaryDirectory() + "qstatus_test_\(UUID().uuidString).sqlite3"
    let db = try DatabaseQueue(path: tmp)
    try db.write { db in
        try db.execute(sql: "CREATE TABLE conversations (key TEXT PRIMARY KEY, value TEXT)")
        for conv in conversations {
            try db.execute(sql: "INSERT INTO conversations (key, value) VALUES (?, ?)", arguments: [conv.key, conv.json])
        }
    }
    return tmp
}

private func makeConversationJSON(
    historyEntries: [(role: String, text: String, timestamp: String)],
    modelId: String = "claude-3-sonnet",
    contextWindowTokens: Int = 200_000,
    cwd: String = "/test/project"
) -> String {
    var historyItems: [String] = []
    for entry in historyEntries {
        let item: String
        if entry.role == "user" {
            item = """
            {"user":{"content":"\(entry.text)","timestamp":"\(entry.timestamp)","created_at":"\(entry.timestamp)"}}
            """
        } else {
            item = """
            {"assistant":{"content":"\(entry.text)","timestamp":"\(entry.timestamp)","created_at":"\(entry.timestamp)"}}
            """
        }
        historyItems.append(item)
    }
    let historyJSON = "[" + historyItems.joined(separator: ",") + "]"
    return """
    {
      "model_info": {"model_id": "\(modelId)", "context_window_tokens": \(contextWindowTokens)},
      "env_context": {"env_state": {"current_working_directory": "\(cwd)"}},
      "history": \(historyJSON),
      "context_manager": {"context_files": []},
      "tool_manager": {},
      "system_prompts": "You are a helpful assistant."
    }
    """
}

private func iso(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    return f.string(from: date)
}

// MARK: - BUG-1: Period metrics are all-time totals

@Suite("BUG-1: Period metrics filtering")
struct Bug1PeriodMetricsTests {

    @Test("Daily metrics exclude yesterday's data")
    func dailyMetricsExcludeYesterdayData() async throws {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: now))!

        let dbPath = try makeTestDB(conversations: [
            ("old-session", makeConversationJSON(
                historyEntries: [
                    ("user", String(repeating: "x", count: 4000), iso(yesterday)),
                    ("assistant", String(repeating: "y", count: 4000), iso(yesterday))
                ]
            )),
            ("today-session", makeConversationJSON(
                historyEntries: [
                    ("user", String(repeating: "a", count: 400), iso(now)),
                    ("assistant", String(repeating: "b", count: 400), iso(now))
                ]
            ))
        ])
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let reader = QDBReader(config: QDBConfig(dbPath: dbPath))
        let periods = try await reader.fetchPeriodTokensByModel(now: now)

        let totalDayTokens = periods.reduce(0) { $0 + $1.dayTokens }
        let totalWeekTokens = periods.reduce(0) { $0 + $1.weekTokens }

        #expect(totalDayTokens < totalWeekTokens,
            "Daily tokens (\(totalDayTokens)) should be less than weekly tokens (\(totalWeekTokens)) when yesterday has more data")
    }

    @Test("Weekly metrics exclude last week's data")
    func weeklyMetricsExcludeLastWeekData() async throws {
        let now = Date()
        let cal = Calendar.current
        let twoWeeksAgo = cal.date(byAdding: .weekOfYear, value: -2, to: now)!

        let dbPath = try makeTestDB(conversations: [
            ("old-session", makeConversationJSON(
                historyEntries: [
                    ("user", String(repeating: "x", count: 8000), iso(twoWeeksAgo)),
                    ("assistant", String(repeating: "y", count: 8000), iso(twoWeeksAgo))
                ]
            )),
            ("today-session", makeConversationJSON(
                historyEntries: [
                    ("user", String(repeating: "a", count: 400), iso(now)),
                    ("assistant", String(repeating: "b", count: 400), iso(now))
                ]
            ))
        ])
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let reader = QDBReader(config: QDBConfig(dbPath: dbPath))
        let periods = try await reader.fetchPeriodTokensByModel(now: now)

        let totalWeekTokens = periods.reduce(0) { $0 + $1.weekTokens }
        let totalYearTokens = periods.reduce(0) { $0 + $1.yearTokens }

        #expect(totalWeekTokens < totalYearTokens,
            "Weekly tokens (\(totalWeekTokens)) should be less than yearly tokens (\(totalYearTokens)) when 2 weeks ago has more data")
    }
}

// MARK: - BUG-2: Context window hardcoded to 175k

@Suite("BUG-2: Context window preservation")
struct Bug2ContextWindowTests {

    @Test("Sessions preserve per-session context window from DB")
    func preservesPerSessionContextWindow() async throws {
        let now = Date()
        let dbPath = try makeTestDB(conversations: [
            ("session-200k", makeConversationJSON(
                historyEntries: [
                    ("user", "question", iso(now)),
                    ("assistant", "answer", iso(now))
                ],
                contextWindowTokens: 200_000
            )),
            ("session-128k", makeConversationJSON(
                historyEntries: [
                    ("user", "question", iso(now)),
                    ("assistant", "answer", iso(now))
                ],
                contextWindowTokens: 128_000
            ))
        ])
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let reader = QDBReader(config: QDBConfig(dbPath: dbPath))
        let sessions = try await reader.fetchSessions(limit: 50, offset: 0, groupByFolder: false, activeOnly: false)

        let session200k = sessions.first { $0.id == "session-200k" }
        let session128k = sessions.first { $0.id == "session-128k" }

        #expect(session200k != nil)
        #expect(session128k != nil)
        #expect(session200k?.contextWindow == 200_000,
            "200k session should have contextWindow=200000, got \(session200k?.contextWindow ?? -1)")
        #expect(session128k?.contextWindow == 128_000,
            "128k session should have contextWindow=128000, got \(session128k?.contextWindow ?? -1)")
    }
}

// MARK: - BUG-3: Latest session = rowid, not activity

@Suite("BUG-3: Latest session by activity")
struct Bug3LatestSessionTests {

    @Test("Latest session determined by activity timestamp, not rowid")
    func latestSessionByActivityNotRowid() async throws {
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        let fiveMinutesAgo = now.addingTimeInterval(-300)

        // First inserted (lower rowid) but MORE RECENT activity
        // Second inserted (higher rowid) but OLDER activity
        let dbPath = try makeTestDB(conversations: [
            ("active-session", makeConversationJSON(
                historyEntries: [
                    ("user", "recent question", iso(fiveMinutesAgo)),
                    ("assistant", "recent answer", iso(fiveMinutesAgo))
                ]
            )),
            ("stale-session", makeConversationJSON(
                historyEntries: [
                    ("user", "old question", iso(oneHourAgo)),
                    ("assistant", "old answer", iso(oneHourAgo))
                ]
            ))
        ])
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let reader = QDBReader(config: QDBConfig(dbPath: dbPath))
        let usage = try await reader.fetchLatestUsage()

        #expect(usage.conversationId == "active-session",
            "Latest session should be determined by activity timestamp, not rowid. Got: \(usage.conversationId ?? "nil")")
    }
}

// MARK: - BUG-4: Monthly message count has no month filter

@Suite("BUG-4: Monthly message count filtering")
struct Bug4MonthlyMessageCountTests {

    @Test("Monthly message count only includes current month")
    func monthlyMessageCountFiltersToCurrentMonth() async throws {
        let now = Date()
        let cal = Calendar.current
        let twoMonthsAgo = cal.date(byAdding: .month, value: -2, to: now)!

        let dbPath = try makeTestDB(conversations: [
            ("old-session", makeConversationJSON(
                historyEntries: [
                    ("user", "old msg 1", iso(twoMonthsAgo)),
                    ("assistant", "old reply 1", iso(twoMonthsAgo)),
                    ("user", "old msg 2", iso(twoMonthsAgo)),
                    ("assistant", "old reply 2", iso(twoMonthsAgo)),
                    ("user", "old msg 3", iso(twoMonthsAgo)),
                    ("assistant", "old reply 3", iso(twoMonthsAgo)),
                    ("user", "old msg 4", iso(twoMonthsAgo)),
                    ("assistant", "old reply 4", iso(twoMonthsAgo)),
                    ("user", "old msg 5", iso(twoMonthsAgo)),
                    ("assistant", "old reply 5", iso(twoMonthsAgo))
                ]
            )),
            ("current-session", makeConversationJSON(
                historyEntries: [
                    ("user", "new msg", iso(now)),
                    ("assistant", "new reply", iso(now))
                ]
            ))
        ])
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let reader = QDBReader(config: QDBConfig(dbPath: dbPath))
        let monthlyCount = try await reader.fetchMonthlyMessageCount(now: now)

        #expect(monthlyCount == 2,
            "Monthly message count should only include current month. Got \(monthlyCount), expected 2")
    }
}

// MARK: - BUG-5: Three divergent token estimators

@Suite("BUG-5: Token estimator consistency")
struct Bug5TokenEstimatorTests {

    @Test("Golden case: 4000 chars = 1000 tokens")
    func estimateGoldenCase4000chars() {
        let result = TokenEstimator.estimate(charCount: 4000)
        #expect(result == 1000, "4000 chars should yield exactly 1000 tokens. Got \(result)")
    }

    @Test("Golden case: 4001 chars = 1000 tokens")
    func estimateGoldenCase4001chars() {
        let result = TokenEstimator.estimate(charCount: 4001)
        #expect(result == 1000, "4001 chars should yield 1000 tokens. Got \(result)")
    }

    @Test("All code paths produce consistent results")
    func estimatorIsConsistentAcrossAllCodePaths() {
        let charCount = 4000

        // Path 1: The canonical estimate(charCount:) method
        let canonical = TokenEstimator.estimate(charCount: charCount)

        // Path 2: Via Breakdown with only fallback chars
        let breakdown = TokenEstimator.Breakdown(
            historyChars: 0, contextFilesChars: 0, toolsChars: 0, systemChars: 0,
            fallbackChars: charCount
        )
        let viaBreakdown = TokenEstimator.estimateTokens(breakdown: breakdown)

        // Path 3: Via the JSON slow-path estimate(from:)
        let jsonStr = String(repeating: "x", count: charCount)
        let viaJSON = TokenEstimator.estimate(from: jsonStr)

        #expect(canonical == viaBreakdown,
            "estimate(charCount:) (\(canonical)) should match estimateTokens(breakdown:) (\(viaBreakdown))")
        #expect(canonical == viaJSON.tokens,
            "estimate(charCount:) (\(canonical)) should match estimate(from:) (\(viaJSON.tokens))")
    }
}

// MARK: - BUG-6: sessionCount(activeOnly:) ignores the parameter

@Suite("BUG-6: sessionCount activeOnly filter")
struct Bug6SessionCountTests {

    @Test("activeOnly count matches activeOnly fetch")
    func activeOnlyCountMatchesActiveOnlyFetch() async throws {
        let now = Date()
        let twoWeeksAgo = now.addingTimeInterval(-14 * 24 * 3600)

        let dbPath = try makeTestDB(conversations: [
            ("old-session", makeConversationJSON(
                historyEntries: [
                    ("user", "old msg", iso(twoWeeksAgo)),
                    ("assistant", "old reply", iso(twoWeeksAgo))
                ]
            )),
            ("active-session", makeConversationJSON(
                historyEntries: [
                    ("user", "recent msg", iso(now)),
                    ("assistant", "recent reply", iso(now))
                ]
            ))
        ])
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let reader = QDBReader(config: QDBConfig(dbPath: dbPath))

        let totalCount = try await reader.sessionCount(activeOnly: false)
        let activeCount = try await reader.sessionCount(activeOnly: true)

        #expect(totalCount == 2, "Total count should be 2")
        #expect(activeCount < totalCount,
            "Active count (\(activeCount)) should be less than total (\(totalCount)) when old sessions exist")

        let activeSessions = try await reader.fetchSessions(limit: 100, offset: 0, groupByFolder: false, activeOnly: true)
        #expect(activeCount == activeSessions.count,
            "sessionCount(activeOnly: true) (\(activeCount)) should match fetchSessions(activeOnly: true).count (\(activeSessions.count))")
    }
}
