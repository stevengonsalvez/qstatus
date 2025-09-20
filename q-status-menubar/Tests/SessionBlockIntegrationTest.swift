// ABOUTME: Integration test for SessionBlockCalculator in the DropdownView UI
// This file tests that the 5-hour billing block information is correctly displayed

import XCTest
@testable import Core
@testable import App

final class SessionBlockIntegrationTest: XCTestCase {

    func testActiveSessionDataIncludesBlockInfo() throws {
        // Create sample entries for testing
        let now = Date()
        let twoHoursAgo = now.addingTimeInterval(-2 * 3600)

        let entry1 = ClaudeUsageEntry(
            timestamp: ISO8601DateFormatter().string(from: twoHoursAgo),
            sessionId: "test-session",
            message: ClaudeMessage(
                id: "msg1",
                type: "response",
                role: "assistant",
                model: "claude-3-5-sonnet",
                content: [],
                usage: ClaudeMessage.Usage(
                    input_tokens: 1000,
                    output_tokens: 500,
                    cache_creation_input_tokens: 100,
                    cache_read_input_tokens: 200
                )
            ),
            costUSD: 0.05,
            requestId: "req1",
            cwd: "/test/project",
            version: "1.0.0",
            isApiErrorMessage: false
        )

        let entry2 = ClaudeUsageEntry(
            timestamp: ISO8601DateFormatter().string(from: now),
            sessionId: "test-session",
            message: ClaudeMessage(
                id: "msg2",
                type: "response",
                role: "assistant",
                model: "claude-3-5-sonnet",
                content: [],
                usage: ClaudeMessage.Usage(
                    input_tokens: 2000,
                    output_tokens: 1000,
                    cache_creation_input_tokens: 200,
                    cache_read_input_tokens: 400
                )
            ),
            costUSD: 0.10,
            requestId: "req2",
            cwd: "/test/project",
            version: "1.0.0",
            isApiErrorMessage: false
        )

        // Test SessionBlockCalculator
        let blocks = SessionBlockCalculator.identifySessionBlocks(entries: [entry1, entry2])

        XCTAssertFalse(blocks.isEmpty, "Should have at least one block")

        if let firstBlock = blocks.first {
            XCTAssertTrue(firstBlock.isActive, "First block should be active")
            XCTAssertEqual(firstBlock.entries.count, 2, "Block should contain both entries")
            XCTAssertEqual(firstBlock.tokenCounts.inputTokens, 3000, "Should sum input tokens")
            XCTAssertEqual(firstBlock.tokenCounts.outputTokens, 1500, "Should sum output tokens")
            XCTAssertEqual(firstBlock.costUSD, 0.15, "Should sum costs", accuracy: 0.01)

            // Verify block timing
            let blockDuration = firstBlock.endTime.timeIntervalSince(firstBlock.startTime)
            XCTAssertEqual(blockDuration, 5 * 3600, "Block should be 5 hours long", accuracy: 1.0)
        }
    }

    func testBlockNumbering() throws {
        // Create entries spanning multiple blocks
        let now = Date()
        var entries: [ClaudeUsageEntry] = []

        // Create entries at 0, 6, and 12 hours ago (3 separate blocks)
        for hoursAgo in [12, 6, 0] {
            let timestamp = now.addingTimeInterval(-Double(hoursAgo) * 3600)
            let entry = ClaudeUsageEntry(
                timestamp: ISO8601DateFormatter().string(from: timestamp),
                sessionId: "test-session",
                message: ClaudeMessage(
                    id: "msg-\(hoursAgo)",
                    type: "response",
                    role: "assistant",
                    model: "claude-3-5-sonnet",
                    content: [],
                    usage: ClaudeMessage.Usage(
                        input_tokens: 1000,
                        output_tokens: 500,
                        cache_creation_input_tokens: nil,
                        cache_read_input_tokens: nil
                    )
                ),
                costUSD: 0.05,
                requestId: "req-\(hoursAgo)",
                cwd: "/test/project",
                version: "1.0.0",
                isApiErrorMessage: false
            )
            entries.append(entry)
        }

        let blocks = SessionBlockCalculator.identifySessionBlocks(entries: entries)

        // Should have 3 blocks (one for each 5-hour period)
        XCTAssertEqual(blocks.count, 3, "Should have 3 separate blocks")

        // Verify last block is active
        if let lastBlock = blocks.last {
            XCTAssertTrue(lastBlock.isActive, "Most recent block should be active")
        }
    }
}