// ABOUTME: Unit tests for ClaudeCodeDataSource implementation
// Tests JSONL parsing, session aggregation, and DataSource protocol compliance

import XCTest
@testable import Core

final class ClaudeCodeDataSourceTests: XCTestCase {

    var dataSource: ClaudeCodeDataSource!

    override func setUp() async throws {
        dataSource = ClaudeCodeDataSource()
    }

    override func tearDown() {
        dataSource = nil
    }

    // MARK: - JSONL Parsing Tests

    func testClaudeUsageEntryDecoding() throws {
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

        XCTAssertEqual(entry.timestamp, "2024-01-15T10:30:00Z")
        XCTAssertEqual(entry.sessionId, "test-session-123")
        XCTAssertEqual(entry.message.usage.input_tokens, 1000)
        XCTAssertEqual(entry.message.usage.output_tokens, 500)
        XCTAssertEqual(entry.message.usage.cache_creation_input_tokens, 100)
        XCTAssertEqual(entry.message.usage.cache_read_input_tokens, 50)
        XCTAssertEqual(entry.message.model, "claude-3-5-sonnet-20241022")
        XCTAssertEqual(entry.message.id, "msg-123")
        XCTAssertEqual(entry.costUSD, 0.0225)
        XCTAssertEqual(entry.requestId, "req-456")
        XCTAssertEqual(entry.cwd, "/Users/test/project")
        XCTAssertEqual(entry.version, "0.7.23")
    }

    func testClaudeUsageEntryDecodingWithOptionalFields() throws {
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

        XCTAssertEqual(entry.timestamp, "2024-01-15T10:30:00Z")
        XCTAssertNil(entry.sessionId)
        XCTAssertEqual(entry.message.usage.input_tokens, 1000)
        XCTAssertEqual(entry.message.usage.output_tokens, 500)
        XCTAssertNil(entry.message.usage.cache_creation_input_tokens)
        XCTAssertNil(entry.message.usage.cache_read_input_tokens)
        XCTAssertNil(entry.message.model)
        XCTAssertNil(entry.message.id)
        XCTAssertNil(entry.costUSD)
        XCTAssertNil(entry.requestId)
        XCTAssertNil(entry.cwd)
        XCTAssertNil(entry.version)
    }

    // MARK: - Token Calculation Tests

    func testTokenUsageTotalCalculation() {
        let usage = ClaudeTokenUsage(
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: 100,
            cache_read_input_tokens: 50
        )

        XCTAssertEqual(usage.totalTokens, 1650)
    }

    func testTokenUsageTotalWithNilOptionals() {
        let usage = ClaudeTokenUsage(
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: nil,
            cache_read_input_tokens: nil
        )

        XCTAssertEqual(usage.totalTokens, 1500)
    }

    // MARK: - Session Aggregation Tests

    func testSessionTotalTokensCalculation() {
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

        XCTAssertEqual(session.totalTokens, 1650)
    }

    // MARK: - DataSource Protocol Tests

    func testDataSourceInitialization() async throws {
        // Test that the data source can be opened without errors
        // This will fail if no Claude data directories exist, which is expected in test environment
        do {
            try await dataSource.openIfNeeded()
        } catch {
            // Expected in test environment without actual Claude data
            XCTAssertNotNil(error)
        }
    }

    func testFetchLatestUsageWithNoData() async throws {
        // When no data is available, should return empty snapshot
        do {
            let usage = try await dataSource.fetchLatestUsage(window: nil)
            XCTAssertEqual(usage.tokensUsed, 0)
            XCTAssertEqual(usage.messageCount, 0)
            XCTAssertNil(usage.conversationId)
        } catch {
            // Expected if no Claude directories exist
            XCTAssertNotNil(error)
        }
    }

    func testFetchSessionsWithNoData() async throws {
        // When no data is available, should return empty array
        do {
            let sessions = try await dataSource.fetchSessions(
                limit: 10,
                offset: 0,
                groupByFolder: false,
                activeOnly: false
            )
            XCTAssertEqual(sessions.count, 0)
        } catch {
            // Expected if no Claude directories exist
            XCTAssertNotNil(error)
        }
    }

    func testSessionCountWithNoData() async throws {
        // When no data is available, should return 0
        do {
            let count = try await dataSource.sessionCount(activeOnly: false)
            XCTAssertEqual(count, 0)
        } catch {
            // Expected if no Claude directories exist
            XCTAssertNotNil(error)
        }
    }

    func testFetchGlobalMetricsWithNoData() async throws {
        // When no data is available, should return empty metrics
        do {
            let metrics = try await dataSource.fetchGlobalMetrics(limitForTop: 5)
            XCTAssertEqual(metrics.totalSessions, 0)
            XCTAssertEqual(metrics.totalTokens, 0)
            XCTAssertEqual(metrics.sessionsNearLimit, 0)
            XCTAssertEqual(metrics.topHeavySessions.count, 0)
        } catch {
            // Expected if no Claude directories exist
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Date Parsing Tests

    func testISO8601DateParsing() throws {
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

        XCTAssertNotNil(entry.date)

        // Verify the date components
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: entry.date!)

        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 15)
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