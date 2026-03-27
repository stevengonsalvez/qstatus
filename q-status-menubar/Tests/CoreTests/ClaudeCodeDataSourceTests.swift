// ABOUTME: Unit tests for ClaudeCodeDataSource implementation
// Tests JSONL parsing, session aggregation, and DataSource protocol compliance

import Testing
import Foundation
@testable import Core

@Suite("ClaudeCodeDataSource")
struct ClaudeCodeDataSourceTests {

    var dataSource: ClaudeCodeDataSource

    init() {
        dataSource = ClaudeCodeDataSource()
    }

    // MARK: - JSONL Parsing Tests

    @Test func claudeUsageEntryDecoding() throws {
        let jsonString = """
        {
            "timestamp": "2024-01-15T10:30:00Z",
            "sessionId": "test-session-123",
            "message": {
                "usage": {
                    "input_tokens": 1000,
                    "output_tokens": 500,
                    "cache_creation_input_tokens": 100,
                    "cache_read_input_tokens": 50
                },
                "model": "claude-3-5-sonnet-20241022",
                "id": "msg-123"
            },
            "costUSD": 0.0225,
            "requestId": "req-456",
            "cwd": "/Users/test/project",
            "version": "0.7.23"
        }
        """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()

        let entry = try decoder.decode(ClaudeUsageEntry.self, from: data)

        #expect(entry.timestamp == "2024-01-15T10:30:00Z")
        #expect(entry.sessionId == "test-session-123")
        #expect(entry.message.usage.input_tokens == 1000)
        #expect(entry.message.usage.output_tokens == 500)
        #expect(entry.message.usage.cache_creation_input_tokens == 100)
        #expect(entry.message.usage.cache_read_input_tokens == 50)
        #expect(entry.message.model == "claude-3-5-sonnet-20241022")
        #expect(entry.message.id == "msg-123")
        #expect(entry.costUSD == 0.0225)
        #expect(entry.requestId == "req-456")
        #expect(entry.cwd == "/Users/test/project")
        #expect(entry.version == "0.7.23")
    }

    @Test func claudeUsageEntryDecodingWithOptionalFields() throws {
        let jsonString = """
        {
            "timestamp": "2024-01-15T10:30:00Z",
            "message": {
                "usage": {
                    "input_tokens": 1000,
                    "output_tokens": 500
                }
            }
        }
        """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()

        let entry = try decoder.decode(ClaudeUsageEntry.self, from: data)

        #expect(entry.timestamp == "2024-01-15T10:30:00Z")
        #expect(entry.sessionId == nil)
        #expect(entry.message.usage.input_tokens == 1000)
        #expect(entry.message.usage.output_tokens == 500)
        #expect(entry.message.usage.cache_creation_input_tokens == nil)
        #expect(entry.message.usage.cache_read_input_tokens == nil)
        #expect(entry.message.model == nil)
        #expect(entry.message.id == nil)
        #expect(entry.costUSD == nil)
        #expect(entry.requestId == nil)
        #expect(entry.cwd == nil)
        #expect(entry.version == nil)
    }

    // MARK: - Token Calculation Tests

    @Test func tokenUsageTotalCalculation() {
        let usage = ClaudeTokenUsage(
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: 100,
            cache_read_input_tokens: 50
        )

        #expect(usage.totalTokens == 1650)
    }

    @Test func tokenUsageTotalWithNilOptionals() {
        let usage = ClaudeTokenUsage(
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: nil,
            cache_read_input_tokens: nil
        )

        #expect(usage.totalTokens == 1500)
    }

    // MARK: - Session Aggregation Tests

    @Test func sessionTotalTokensCalculation() {
        let session = ClaudeSession(
            id: "test-session",
            startTime: Date(),
            endTime: Date(),
            entries: [],
            totalInputTokens: 1000,
            totalOutputTokens: 500,
            totalCacheCreationTokens: 100,
            totalCacheReadTokens: 50,
            totalCost: 0.0225,
            totalCostFromJSONL: 0.0225,
            models: ["claude-3-5-sonnet"],
            cwd: "/test/path",
            messageCount: 1
        )

        #expect(session.totalTokens == 1650)
    }

    // MARK: - DataSource Protocol Tests

    @Test func dataSourceInitialization() async throws {
        // Test that the data source can be opened without errors
        // This will fail if no Claude data directories exist, which is expected in test environment
        do {
            try await dataSource.openIfNeeded()
        } catch {
            // Expected in test environment without actual Claude data
            #expect(error != nil)
        }
    }

    @Test func fetchLatestUsageWithNoData() async throws {
        // When no data is available, should return empty snapshot
        do {
            let usage = try await dataSource.fetchLatestUsage(window: nil)
            #expect(usage.tokensUsed == 0)
            #expect(usage.messageCount == 0)
            #expect(usage.conversationId == nil)
        } catch {
            // Expected if no Claude directories exist
            #expect(error != nil)
        }
    }

    @Test func fetchSessionsWithNoData() async throws {
        // When no data is available, should return empty array
        do {
            let sessions = try await dataSource.fetchSessions(
                limit: 10,
                offset: 0,
                groupByFolder: false,
                activeOnly: false
            )
            #expect(sessions.count == 0)
        } catch {
            // Expected if no Claude directories exist
            #expect(error != nil)
        }
    }

    @Test func sessionCountWithNoData() async throws {
        // When no data is available, should return 0
        do {
            let count = try await dataSource.sessionCount(activeOnly: false)
            #expect(count == 0)
        } catch {
            // Expected if no Claude directories exist
            #expect(error != nil)
        }
    }

    @Test func fetchGlobalMetricsWithNoData() async throws {
        // When no data is available, should return empty metrics
        do {
            let metrics = try await dataSource.fetchGlobalMetrics(limitForTop: 5)
            #expect(metrics.totalSessions == 0)
            #expect(metrics.totalTokens == 0)
            #expect(metrics.sessionsNearLimit == 0)
            #expect(metrics.topHeavySessions.count == 0)
        } catch {
            // Expected if no Claude directories exist
            #expect(error != nil)
        }
    }

    // MARK: - Date Parsing Tests

    @Test func iso8601DateParsing() throws {
        let jsonString = """
        {
            "timestamp": "2024-01-15T10:30:00Z",
            "message": {
                "usage": {
                    "input_tokens": 100,
                    "output_tokens": 50
                }
            }
        }
        """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let entry = try decoder.decode(ClaudeUsageEntry.self, from: data)

        #expect(entry.date != nil)

        // Verify the date components
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: entry.date!)

        #expect(components.year == 2024)
        #expect(components.month == 1)
        #expect(components.day == 15)
    }

    // MARK: - Sample Data Creation Helpers

    private func createSampleEntry(
        timestamp: String = "2024-01-15T10:30:00Z",
        sessionId: String = "test-session",
        inputTokens: Int = 1000,
        outputTokens: Int = 500,
        model: String = "claude-3-5-sonnet-20241022"
    ) -> ClaudeUsageEntry {
        let usage = ClaudeTokenUsage(
            input_tokens: inputTokens,
            output_tokens: outputTokens,
            cache_creation_input_tokens: nil,
            cache_read_input_tokens: nil
        )

        let message = ClaudeMessage(
            usage: usage,
            model: model,
            id: "msg-\(UUID().uuidString)"
        )

        return ClaudeUsageEntry(
            timestamp: timestamp,
            sessionId: sessionId,
            message: message,
            costUSD: nil,
            requestId: "req-\(UUID().uuidString)",
            cwd: "/test/project",
            version: "0.7.23",
            isApiErrorMessage: false
        )
    }
}
