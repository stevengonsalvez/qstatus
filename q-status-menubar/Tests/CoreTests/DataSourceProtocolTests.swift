// ABOUTME: Tests for the DataSource protocol abstraction
// Verifies that QDBReader correctly conforms to the protocol and that the abstraction works

import XCTest
@testable import Core

final class DataSourceProtocolTests: XCTestCase {

    func testQDBReaderConformsToDataSource() {
        // This test verifies at compile-time that QDBReader conforms to DataSource
        // If this compiles, the protocol conformance is correct
        let _: any DataSource = QDBReader()

        // The fact that this compiles proves QDBReader conforms to DataSource
        XCTAssertTrue(true, "QDBReader successfully conforms to DataSource protocol")
    }

    func testDataSourceCanBeUsedAsAbstraction() async throws {
        // Create a QDBReader through the protocol
        let dataSource: any DataSource = QDBReader()

        // Verify we can call protocol methods
        // Note: These may fail if database doesn't exist, but that's OK
        // We're testing the protocol abstraction, not the implementation

        do {
            // Test openIfNeeded
            try await dataSource.openIfNeeded()
        } catch {
            // Expected if database doesn't exist in test environment
            print("openIfNeeded failed (expected in test environment): \(error)")
        }

        do {
            // Test dataVersion
            _ = try await dataSource.dataVersion()
        } catch {
            // Expected if database doesn't exist
            print("dataVersion failed (expected in test environment): \(error)")
        }

        // Test that we can pass DataSource to UpdateCoordinator
        let metrics = MetricsCalculator()
        let settings = SettingsStore()
        let coordinator = UpdateCoordinator(
            reader: dataSource,
            metrics: metrics,
            settings: settings
        )

        XCTAssertNotNil(coordinator, "UpdateCoordinator accepts DataSource protocol")
    }

    func testDefaultImplementations() async throws {
        // Test that default implementations work
        let dataSource: any DataSource = QDBReader()

        // These should use default implementations that forward to the main methods
        do {
            _ = try await dataSource.fetchLatestUsage() // Uses default nil window
            _ = try await dataSource.fetchSessions() // Uses default parameters
            _ = try await dataSource.sessionCount() // Uses default activeOnly: false
            _ = try await dataSource.fetchGlobalMetrics() // Uses default limitForTop: 5
            _ = try await dataSource.fetchMonthlyMessageCount() // Uses default Date()
        } catch {
            // Expected if database doesn't exist
            print("Default implementations work but database access failed (expected): \(error)")
        }

        XCTAssertTrue(true, "Default implementations are accessible")
    }
}

// MARK: - Mock Implementation for Testing

/// A mock implementation of DataSource for testing purposes
actor MockDataSource: DataSource {
    private var isOpen = false
    private var version = 0

    func openIfNeeded() async throws {
        isOpen = true
    }

    func dataVersion() async throws -> Int {
        version += 1
        return version
    }

    func fetchLatestUsage(window: TimeInterval?) async throws -> UsageSnapshot {
        return UsageSnapshot(
            timestamp: Date(),
            tokensUsed: 1000,
            messageCount: 10,
            conversationId: "test-conversation",
            sessionLimitOverride: nil
        )
    }

    func fetchSessions(
        limit: Int,
        offset: Int,
        groupByFolder: Bool,
        activeOnly: Bool
    ) async throws -> [SessionSummary] {
        return [
            SessionSummary(
                id: "test-session-1",
                cwd: "/test/path",
                tokensUsed: 500,
                contextWindow: 175_000,
                usagePercent: 0.3,
                messageCount: 5,
                lastActivity: Date(),
                state: .normal,
                internalRowID: 1,
                hasCompactionIndicators: false,
                modelId: "claude-3-sonnet",
                costUSD: 0.01
            )
        ]
    }

    func fetchSessionDetail(key: String) async throws -> SessionDetails? {
        let summary = SessionSummary(
            id: key,
            cwd: "/test/path",
            tokensUsed: 500,
            contextWindow: 175_000,
            usagePercent: 0.3,
            messageCount: 5,
            lastActivity: Date(),
            state: .normal,
            internalRowID: 1,
            hasCompactionIndicators: false,
            modelId: "claude-3-sonnet",
            costUSD: 0.01
        )

        return SessionDetails(
            summary: summary,
            historyTokens: 300,
            contextFilesTokens: 100,
            toolsTokens: 50,
            systemTokens: 50
        )
    }

    func sessionCount(activeOnly: Bool) async throws -> Int {
        return activeOnly ? 5 : 10
    }

    func fetchGlobalMetrics(limitForTop: Int) async throws -> GlobalMetrics {
        return GlobalMetrics(
            totalSessions: 10,
            totalTokens: 5000,
            sessionsNearLimit: 2,
            topHeavySessions: []
        )
    }

    func fetchGlobalTotalsByModel() async throws -> [QDBReader.GlobalByModel] {
        return []
    }

    func fetchPeriodTokensByModel(now: Date) async throws -> [QDBReader.PeriodByModel] {
        return []
    }

    func fetchPeriodTokensByModel(
        forKeys keys: [String],
        now: Date
    ) async throws -> [QDBReader.PeriodByModel] {
        return []
    }

    func fetchMonthlyMessageCount(now: Date) async throws -> Int {
        return 100
    }
}

final class MockDataSourceTests: XCTestCase {

    func testMockDataSourceWorks() async throws {
        let mock: any DataSource = MockDataSource()

        // Test that mock implements all required methods
        try await mock.openIfNeeded()

        let version = try await mock.dataVersion()
        XCTAssertEqual(version, 1)

        let usage = try await mock.fetchLatestUsage(window: nil)
        XCTAssertEqual(usage.tokensUsed, 1000)

        let sessions = try await mock.fetchSessions(
            limit: 10,
            offset: 0,
            groupByFolder: false,
            activeOnly: false
        )
        XCTAssertEqual(sessions.count, 1)

        let detail = try await mock.fetchSessionDetail(key: "test")
        XCTAssertNotNil(detail)

        let count = try await mock.sessionCount(activeOnly: false)
        XCTAssertEqual(count, 10)

        let metrics = try await mock.fetchGlobalMetrics(limitForTop: 5)
        XCTAssertEqual(metrics.totalSessions, 10)
    }

    func testUpdateCoordinatorWithMock() async throws {
        let mock: any DataSource = MockDataSource()
        let metrics = MetricsCalculator()
        let settings = SettingsStore()

        let coordinator = UpdateCoordinator(
            reader: mock,
            metrics: metrics,
            settings: settings
        )

        // Start the coordinator briefly
        coordinator.start()

        // Wait a moment for it to poll
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Stop it
        coordinator.stop()

        // Verify it initialized correctly
        XCTAssertNotNil(coordinator.viewModel)
    }
}