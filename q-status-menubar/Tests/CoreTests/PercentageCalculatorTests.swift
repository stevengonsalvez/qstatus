// ABOUTME: Tests for PercentageCalculator ensuring consistent percentage calculations across the app
// Tests cover all percentage calculation methods including Claude token limit calculations

import XCTest
@testable import Core

final class PercentageCalculatorTests: XCTestCase {

    // MARK: - Token Percentage Tests

    func testCalculateTokenPercentage_withValidInputs() {
        // Test token percentage calculation with valid inputs
        let currentTokens = 50000
        let tokenLimit = 200000

        let percentage = PercentageCalculator.calculateTokenPercentage(
            tokens: currentTokens,
            limit: tokenLimit
        )

        XCTAssertEqual(percentage, 25.0, accuracy: 0.01,
                      "Should calculate 25% for 50K tokens out of 200K limit")
    }

    func testCalculateTokenPercentage_withZeroTokens() {
        // Test with zero current tokens
        let percentage = PercentageCalculator.calculateTokenPercentage(
            tokens: 0,
            limit: 200000
        )

        XCTAssertEqual(percentage, 0.0, accuracy: 0.01,
                      "Should return 0% for zero tokens")
    }

    func testCalculateTokenPercentage_withZeroLimit() {
        // Test with zero limit (should return 0 to avoid division by zero)
        let percentage = PercentageCalculator.calculateTokenPercentage(
            tokens: 50000,
            limit: 0
        )

        XCTAssertEqual(percentage, 0.0, accuracy: 0.01,
                      "Should return 0% for zero limit to avoid division by zero")
    }

    func testCalculateTokenPercentage_atLimit() {
        // Test when current tokens equals the limit
        let currentTokens = 200000
        let tokenLimit = 200000

        let percentage = PercentageCalculator.calculateTokenPercentage(
            tokens: currentTokens,
            limit: tokenLimit
        )

        XCTAssertEqual(percentage, 100.0, accuracy: 0.01,
                      "Should return 100% when at token limit")
    }

    func testCalculateTokenPercentage_overLimit_capped() {
        // Test when current tokens exceeds the limit with capping (default behavior)
        let currentTokens = 250000
        let tokenLimit = 200000

        let percentage = PercentageCalculator.calculateTokenPercentage(
            tokens: currentTokens,
            limit: tokenLimit
        )

        XCTAssertEqual(percentage, 100.0, accuracy: 0.01,
                      "Should cap at 100% when exceeding token limit")
    }

    func testCalculateTokenPercentage_overLimit_uncapped() {
        // Test when current tokens exceeds the limit without capping
        let currentTokens = 250000
        let tokenLimit = 200000

        let percentage = PercentageCalculator.calculateTokenPercentage(
            tokens: currentTokens,
            limit: tokenLimit,
            cappedAt100: false
        )

        XCTAssertEqual(percentage, 125.0, accuracy: 0.01,
                      "Should return over 100% when exceeding token limit and uncapped")
    }

    func testCalculateTokenPercentage_consistentWithManualCalculation() {
        // Test that our method matches the original manual calculation
        let currentTokens = 150000
        let tokenLimit = 200000

        let calculatorResult = PercentageCalculator.calculateTokenPercentage(
            tokens: currentTokens,
            limit: tokenLimit,
            cappedAt100: false
        )

        let manualResult = (Double(currentTokens) / Double(tokenLimit)) * 100.0

        XCTAssertEqual(calculatorResult, manualResult, accuracy: 0.01,
                      "PercentageCalculator result should match original manual calculation")
    }
}