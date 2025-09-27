// ABOUTME: Test to verify PercentageCalculator returns 0% when no active session exists
// This test ensures the fix for the ccusage/qstatus discrepancy is working correctly

import XCTest
@testable import Core

class PercentageCalculatorNoSessionTest: XCTestCase {

    func testNoActiveSessionReturnsZeroPercent() {
        // Test with no active session and monthly data available
        let monthlyData = (cost: 20.0, limit: 18.0)  // Cost exceeds limit

        let percentage = PercentageCalculator.calculateCriticalPercentage(
            activeSession: nil,
            maxTokensFromPreviousBlocks: nil,
            monthlyData: monthlyData
        )

        // Should return 0% instead of calculating monthly percentage
        XCTAssertEqual(percentage, 0, "Should return 0% when no active session exists")
    }

    func testNoActiveSessionNoMonthlyDataReturnsZeroPercent() {
        // Test with no active session and no monthly data
        let percentage = PercentageCalculator.calculateCriticalPercentage(
            activeSession: nil,
            maxTokensFromPreviousBlocks: nil,
            monthlyData: nil
        )

        // Should return 0%
        XCTAssertEqual(percentage, 0, "Should return 0% when no active session and no monthly data")
    }

    func testActiveSessionWithoutBlockUsesSessionData() {
        // Create a mock active session without a block
        let activeSession = ActiveSessionData(
            sessionId: "test-session",
            startTime: Date(),
            lastActivity: Date(),
            tokens: 100000,
            cumulativeTokens: 150000,
            cost: 5.0,
            isActive: true,
            messageCount: 10,
            cwd: "/test/path",
            model: "claude-3-5-sonnet-20241022",
            costFromJSONL: true,
            messagesPerHour: 2.0,
            tokensPerHour: 20000,
            costPerHour: 1.0,
            currentBlock: nil,
            blockNumber: 1,
            totalBlocks: 1
        )

        let percentage = PercentageCalculator.calculateCriticalPercentage(
            activeSession: activeSession,
            maxTokensFromPreviousBlocks: 10_000_000,
            monthlyData: nil
        )

        // Should calculate based on session data, not return 0
        XCTAssertGreaterThan(percentage, 0, "Should calculate percentage when active session exists")
    }
}