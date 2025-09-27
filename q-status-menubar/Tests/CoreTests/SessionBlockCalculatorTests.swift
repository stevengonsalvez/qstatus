// ABOUTME: Tests for SessionBlockCalculator - validates session block grouping algorithm
// This file contains comprehensive tests for the 5-hour session block calculator

import XCTest
@testable import Core

final class SessionBlockCalculatorTests: XCTestCase {

    // MARK: - Test Helpers

    private func createMockEntry(
        timestamp: Date,
        inputTokens: Int = 1000,
        outputTokens: Int = 500,
        model: String = "claude-3-5-sonnet-20241022",
        costUSD: Double = 0.01
    ) -> ClaudeUsageEntry {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")

        return ClaudeUsageEntry(
            timestamp: formatter.string(from: timestamp),
            sessionId: "test-session",
            message: ClaudeMessage(
                usage: ClaudeTokenUsage(
                    input_tokens: inputTokens,
                    output_tokens: outputTokens,
                    cache_creation_input_tokens: 0,
                    cache_read_input_tokens: 0
                ),
                model: model,
                id: "msg-\(UUID().uuidString)"
            ),
            costUSD: costUSD,
            requestId: "req-\(UUID().uuidString)",
            cwd: "/test/directory",
            version: "1.0.0",
            isApiErrorMessage: false
        )
    }

    private func createDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second

        return calendar.date(from: components)!
    }

    // MARK: - Basic Functionality Tests

    func testEmptyEntries() {
        let blocks = SessionBlockCalculator.identifySessionBlocks(entries: [])
        XCTAssertEqual(blocks.count, 0, "Should return empty array for empty entries")
    }

    func testSingleBlockWithinFiveHours() {
        let baseTime = createDate(year: 2024, month: 1, day: 1, hour: 10)
        let entries = [
            createMockEntry(timestamp: baseTime),
            createMockEntry(timestamp: baseTime.addingTimeInterval(3600)), // 1 hour later
            createMockEntry(timestamp: baseTime.addingTimeInterval(7200))  // 2 hours later
        ]

        let blocks = SessionBlockCalculator.identifySessionBlocks(entries: entries)

        XCTAssertEqual(blocks.count, 1, "Should create single block for entries within 5 hours")
        XCTAssertEqual(blocks[0].startTime, baseTime, "Block should start at first entry time (floored)")
        XCTAssertEqual(blocks[0].entries.count, 3, "Block should contain all 3 entries")
        XCTAssertEqual(blocks[0].tokenCounts.inputTokens, 3000, "Should aggregate input tokens")
        XCTAssertEqual(blocks[0].tokenCounts.outputTokens, 1500, "Should aggregate output tokens")
        XCTAssertEqual(blocks[0].costUSD, 0.03, accuracy: 0.001, "Should aggregate costs")
    }

    func testMultipleBlocksSpanningMoreThanFiveHours() {
        let baseTime = createDate(year: 2024, month: 1, day: 1, hour: 10)
        let entries = [
            createMockEntry(timestamp: baseTime),
            createMockEntry(timestamp: baseTime.addingTimeInterval(6 * 3600)) // 6 hours later
        ]

        let blocks = SessionBlockCalculator.identifySessionBlocks(entries: entries)

        XCTAssertEqual(blocks.count, 3, "Should create first block, gap block, and second block")
        XCTAssertEqual(blocks[0].entries.count, 1, "First block should have 1 entry")
        XCTAssertTrue(blocks[1].isGap, "Second block should be a gap block")
        XCTAssertEqual(blocks[2].entries.count, 1, "Third block should have 1 entry")
    }

    // MARK: - Gap Detection Tests

    func testGapBlockCreation() {
        let baseTime = createDate(year: 2024, month: 1, day: 1, hour: 10)
        let entries = [
            createMockEntry(timestamp: baseTime),
            createMockEntry(timestamp: baseTime.addingTimeInterval(2 * 3600)), // 2 hours later
            createMockEntry(timestamp: baseTime.addingTimeInterval(8 * 3600))  // 8 hours later
        ]

        let blocks = SessionBlockCalculator.identifySessionBlocks(entries: entries)

        XCTAssertEqual(blocks.count, 3, "Should create first block, gap block, and second block")
        XCTAssertEqual(blocks[0].entries.count, 2, "First block should have 2 entries")
        XCTAssertTrue(blocks[1].isGap, "Second block should be a gap block")
        XCTAssertEqual(blocks[1].entries.count, 0, "Gap block should have no entries")
        XCTAssertEqual(blocks[2].entries.count, 1, "Third block should have 1 entry")
    }

    func testNoGapBlockForShortGaps() {
        let baseTime = createDate(year: 2024, month: 1, day: 1, hour: 10)
        let entries = [
            createMockEntry(timestamp: baseTime),
            createMockEntry(timestamp: baseTime.addingTimeInterval(3 * 3600)) // 3 hours later (within 5 hours)
        ]

        let blocks = SessionBlockCalculator.identifySessionBlocks(entries: entries)

        XCTAssertEqual(blocks.count, 1, "Should create single block without gap")
        XCTAssertEqual(blocks[0].entries.count, 2, "Block should contain both entries")
    }

    // MARK: - Time Handling Tests

    func testFloorToHour() {
        let entryTime = createDate(year: 2024, month: 1, day: 1, hour: 10, minute: 55, second: 30)
        let expectedStartTime = createDate(year: 2024, month: 1, day: 1, hour: 10, minute: 0, second: 0)
        let entries = [createMockEntry(timestamp: entryTime)]

        let blocks = SessionBlockCalculator.identifySessionBlocks(entries: entries)

        XCTAssertEqual(blocks.count, 1, "Should create one block")
        XCTAssertEqual(blocks[0].startTime, expectedStartTime, "Block start time should be floored to hour")

        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        XCTAssertEqual(blocks[0].id, formatter.string(from: expectedStartTime), "Block ID should use floored time")
    }

    func testSortingUnsortedEntries() {
        let baseTime = createDate(year: 2024, month: 1, day: 1, hour: 10)
        let entries = [
            createMockEntry(timestamp: baseTime.addingTimeInterval(2 * 3600)), // 2 hours later
            createMockEntry(timestamp: baseTime),                               // earliest
            createMockEntry(timestamp: baseTime.addingTimeInterval(1 * 3600))  // 1 hour later
        ]

        let blocks = SessionBlockCalculator.identifySessionBlocks(entries: entries)

        XCTAssertEqual(blocks.count, 1, "Should create single block")
        XCTAssertEqual(blocks[0].entries.count, 3, "Block should contain all entries")

        // Verify entries are sorted
        if let firstDate = blocks[0].entries[0].date,
           let secondDate = blocks[0].entries[1].date,
           let thirdDate = blocks[0].entries[2].date {
            XCTAssertLessThan(firstDate, secondDate, "Entries should be sorted")
            XCTAssertLessThan(secondDate, thirdDate, "Entries should be sorted")
        }
    }

    // MARK: - Custom Duration Tests

    func testCustomSessionDuration() {
        let baseTime = createDate(year: 2024, month: 1, day: 1, hour: 10)
        let entries = [
            createMockEntry(timestamp: baseTime),
            createMockEntry(timestamp: baseTime.addingTimeInterval(3 * 3600))  // 3 hours later (beyond 2h limit)
        ]

        // Test with 2-hour duration
        let blocks = SessionBlockCalculator.identifySessionBlocks(entries: entries, sessionDurationHours: 2)

        XCTAssertEqual(blocks.count, 3, "Should create first block, gap block, and second block with 2-hour duration")
        XCTAssertEqual(blocks[0].entries.count, 1, "First block should have 1 entry")
        XCTAssertTrue(blocks[1].isGap, "Second block should be a gap block")
        XCTAssertEqual(blocks[2].entries.count, 1, "Third block should have 1 entry")
    }

    func testVeryShortDuration() {
        let baseTime = createDate(year: 2024, month: 1, day: 1, hour: 10)
        let entries = [
            createMockEntry(timestamp: baseTime),
            createMockEntry(timestamp: baseTime.addingTimeInterval(20 * 60)),  // 20 minutes later
            createMockEntry(timestamp: baseTime.addingTimeInterval(80 * 60))   // 80 minutes later
        ]

        // Test with 0.5 hour (30 minutes) duration
        let blocks = SessionBlockCalculator.identifySessionBlocks(entries: entries, sessionDurationHours: 0.5)

        XCTAssertEqual(blocks.count, 3, "Should create multiple blocks with short duration")
        XCTAssertEqual(blocks[0].entries.count, 2, "First block should have 2 entries within 30 minutes")
        XCTAssertTrue(blocks[1].isGap, "Should have gap block")
        XCTAssertEqual(blocks[2].entries.count, 1, "Last block should have 1 entry")
    }

    // MARK: - Token and Cost Aggregation Tests

    func testTokenAggregation() {
        let baseTime = createDate(year: 2024, month: 1, day: 1, hour: 10)
        let entries = [
            createMockEntry(timestamp: baseTime, inputTokens: 1000, outputTokens: 500),
            createMockEntry(timestamp: baseTime.addingTimeInterval(3600), inputTokens: 2000, outputTokens: 1000),
            createMockEntry(timestamp: baseTime.addingTimeInterval(7200), inputTokens: 1500, outputTokens: 750)
        ]

        let blocks = SessionBlockCalculator.identifySessionBlocks(entries: entries)

        XCTAssertEqual(blocks.count, 1, "Should create single block")
        XCTAssertEqual(blocks[0].tokenCounts.inputTokens, 4500, "Should sum input tokens")
        XCTAssertEqual(blocks[0].tokenCounts.outputTokens, 2250, "Should sum output tokens")
        XCTAssertEqual(blocks[0].tokenCounts.totalTokens, 6750, "Should calculate total tokens correctly")
    }

    func testCacheTokenHandling() {
        let baseTime = createDate(year: 2024, month: 1, day: 1, hour: 10)

        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")

        let entry = ClaudeUsageEntry(
            timestamp: formatter.string(from: baseTime),
            sessionId: "test-session",
            message: ClaudeMessage(
                usage: ClaudeTokenUsage(
                    input_tokens: 1000,
                    output_tokens: 500,
                    cache_creation_input_tokens: 100,
                    cache_read_input_tokens: 200
                ),
                model: "claude-3-5-sonnet",
                id: "msg-123"
            ),
            costUSD: 0.01,
            requestId: "req-123",
            cwd: "/test/dir",
            version: "1.0.0",
            isApiErrorMessage: false
        )

        let blocks = SessionBlockCalculator.identifySessionBlocks(entries: [entry])

        XCTAssertEqual(blocks[0].tokenCounts.cacheCreationInputTokens, 100, "Should track cache creation tokens")
        XCTAssertEqual(blocks[0].tokenCounts.cacheReadInputTokens, 200, "Should track cache read tokens")
        XCTAssertEqual(blocks[0].tokenCounts.totalTokens, 1800, "Should include cache tokens in total")
    }

    func testModelAggregation() {
        let baseTime = createDate(year: 2024, month: 1, day: 1, hour: 10)
        let entries = [
            createMockEntry(timestamp: baseTime, model: "claude-3-5-sonnet"),
            createMockEntry(timestamp: baseTime.addingTimeInterval(3600), model: "claude-3-opus"),
            createMockEntry(timestamp: baseTime.addingTimeInterval(7200), model: "claude-3-5-sonnet")
        ]

        let blocks = SessionBlockCalculator.identifySessionBlocks(entries: entries)

        XCTAssertEqual(blocks.count, 1, "Should create single block")
        XCTAssertEqual(blocks[0].models.count, 2, "Should have 2 unique models")
        XCTAssertTrue(blocks[0].models.contains("claude-3-5-sonnet"), "Should contain sonnet model")
        XCTAssertTrue(blocks[0].models.contains("claude-3-opus"), "Should contain opus model")
    }

    // MARK: - Burn Rate Tests

    func testBurnRateCalculation() {
        let baseTime = createDate(year: 2024, month: 1, day: 1, hour: 10)
        let entries = [
            createMockEntry(timestamp: baseTime, inputTokens: 1000, outputTokens: 500, costUSD: 0.01),
            createMockEntry(timestamp: baseTime.addingTimeInterval(60), inputTokens: 2000, outputTokens: 1000, costUSD: 0.02)
        ]

        let blocks = SessionBlockCalculator.identifySessionBlocks(entries: entries)
        let burnRate = BurnRateCalculator.calculateBurnRate(for: blocks[0])

        XCTAssertNotNil(burnRate, "Should calculate burn rate")
        if let burnRate = burnRate {
            XCTAssertEqual(burnRate.tokensPerMinute, 4500, accuracy: 0.1, "Should calculate 4500 tokens/minute")
            XCTAssertEqual(burnRate.tokensPerMinuteForIndicator, 4500, accuracy: 0.1, "Should calculate indicator rate")
            XCTAssertEqual(burnRate.costPerHour, 1.8, accuracy: 0.01, "Should calculate $1.80/hour")
        }
    }

    func testBurnRateWithCacheTokens() {
        let baseTime = createDate(year: 2024, month: 1, day: 1, hour: 10)

        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")

        let entries = [
            ClaudeUsageEntry(
                timestamp: formatter.string(from: baseTime),
                sessionId: "test",
                message: ClaudeMessage(
                    usage: ClaudeTokenUsage(
                        input_tokens: 1000,
                        output_tokens: 500,
                        cache_creation_input_tokens: 2000,
                        cache_read_input_tokens: 8000
                    ),
                    model: "claude-3-5-sonnet",
                    id: "msg-1"
                ),
                costUSD: 0.01,
                requestId: "req-1",
                cwd: "/test",
                version: "1.0.0",
                isApiErrorMessage: false
            ),
            ClaudeUsageEntry(
                timestamp: formatter.string(from: baseTime.addingTimeInterval(60)),
                sessionId: "test",
                message: ClaudeMessage(
                    usage: ClaudeTokenUsage(
                        input_tokens: 500,
                        output_tokens: 200,
                        cache_creation_input_tokens: 0,
                        cache_read_input_tokens: 0
                    ),
                    model: "claude-3-5-sonnet",
                    id: "msg-2"
                ),
                costUSD: 0.02,
                requestId: "req-2",
                cwd: "/test",
                version: "1.0.0",
                isApiErrorMessage: false
            )
        ]

        let blocks = SessionBlockCalculator.identifySessionBlocks(entries: entries)
        let burnRate = BurnRateCalculator.calculateBurnRate(for: blocks[0])

        XCTAssertNotNil(burnRate, "Should calculate burn rate")
        if let burnRate = burnRate {
            XCTAssertEqual(burnRate.tokensPerMinute, 12200, accuracy: 0.1, "Should include all tokens")
            XCTAssertEqual(burnRate.tokensPerMinuteForIndicator, 2200, accuracy: 0.1, "Should exclude cache tokens for indicator")
        }
    }

    func testBurnRateReturnsNilForEmptyBlock() {
        let block = SessionBlock(
            id: "test",
            startTime: Date(),
            endTime: Date().addingTimeInterval(5 * 3600),
            isActive: true,
            entries: []
        )

        let burnRate = BurnRateCalculator.calculateBurnRate(for: block)
        XCTAssertNil(burnRate, "Should return nil for empty block")
    }

    func testBurnRateReturnsNilForGapBlock() {
        let block = SessionBlock(
            id: "gap-test",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            isGap: true
        )

        let burnRate = BurnRateCalculator.calculateBurnRate(for: block)
        XCTAssertNil(burnRate, "Should return nil for gap block")
    }

    // MARK: - Projection Tests

    func testProjectedUsageReturnsNilForInactiveBlock() {
        let block = SessionBlock(
            id: "test",
            startTime: Date(),
            endTime: Date().addingTimeInterval(5 * 3600),
            isActive: false,
            entries: []
        )

        let projection = ProjectedUsageCalculator.projectBlockUsage(for: block)
        XCTAssertNil(projection, "Should return nil for inactive block")
    }

    func testProjectedUsageReturnsNilForGapBlock() {
        let block = SessionBlock(
            id: "gap-test",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            isActive: true,
            isGap: true
        )

        let projection = ProjectedUsageCalculator.projectBlockUsage(for: block)
        XCTAssertNil(projection, "Should return nil for gap block")
    }

    // MARK: - Filter Tests

    func testFilterRecentBlocks() {
        let now = Date()
        let recentTime = now.addingTimeInterval(-2 * 24 * 3600) // 2 days ago
        let oldTime = now.addingTimeInterval(-5 * 24 * 3600)    // 5 days ago

        let recentBlock = SessionBlock(
            id: "recent",
            startTime: recentTime,
            endTime: recentTime.addingTimeInterval(5 * 3600),
            isActive: false
        )

        let oldBlock = SessionBlock(
            id: "old",
            startTime: oldTime,
            endTime: oldTime.addingTimeInterval(5 * 3600),
            isActive: false
        )

        let blocks = [recentBlock, oldBlock]
        let filtered = SessionBlockFilter.filterRecentBlocks(blocks)

        XCTAssertEqual(filtered.count, 1, "Should filter out old blocks")
        XCTAssertEqual(filtered[0].id, "recent", "Should keep recent block")
    }

    func testFilterIncludesActiveBlocks() {
        let now = Date()
        let oldTime = now.addingTimeInterval(-10 * 24 * 3600) // 10 days ago

        let oldActiveBlock = SessionBlock(
            id: "old-active",
            startTime: oldTime,
            endTime: now.addingTimeInterval(3600), // Still active
            isActive: true
        )

        let blocks = [oldActiveBlock]
        let filtered = SessionBlockFilter.filterRecentBlocks(blocks, days: 3)

        XCTAssertEqual(filtered.count, 1, "Should include active blocks regardless of age")
        XCTAssertTrue(filtered[0].isActive, "Block should be active")
    }

    func testFilterWithCustomDays() {
        let now = Date()
        let withinRange = now.addingTimeInterval(-4 * 24 * 3600)  // 4 days ago
        let outsideRange = now.addingTimeInterval(-8 * 24 * 3600) // 8 days ago

        let withinBlock = SessionBlock(
            id: "within",
            startTime: withinRange,
            endTime: withinRange.addingTimeInterval(5 * 3600),
            isActive: false
        )

        let outsideBlock = SessionBlock(
            id: "outside",
            startTime: outsideRange,
            endTime: outsideRange.addingTimeInterval(5 * 3600),
            isActive: false
        )

        let blocks = [withinBlock, outsideBlock]
        let filtered = SessionBlockFilter.filterRecentBlocks(blocks, days: 7)

        XCTAssertEqual(filtered.count, 1, "Should respect custom day parameter")
        XCTAssertEqual(filtered[0].id, "within", "Should keep block within range")
    }
}