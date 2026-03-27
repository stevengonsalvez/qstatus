// ABOUTME: Tests for PercentageCalculator ensuring consistent percentage calculations across the app
// Tests cover all percentage calculation methods including Claude token limit calculations

import Testing
@testable import Core

@Suite("PercentageCalculator")
struct PercentageCalculatorTests {

    // MARK: - Token Percentage Tests

    @Test func calculateTokenPercentage_withValidInputs() {
        // Test token percentage calculation with valid inputs
        let currentTokens = 50000
        let tokenLimit = 200000

        let percentage = PercentageCalculator.calculateTokenPercentage(
            tokens: currentTokens,
            limit: tokenLimit
        )

        #expect(abs(percentage - 25.0) < 0.01,
               "Should calculate 25% for 50K tokens out of 200K limit")
    }

    @Test func calculateTokenPercentage_withZeroTokens() {
        // Test with zero current tokens
        let percentage = PercentageCalculator.calculateTokenPercentage(
            tokens: 0,
            limit: 200000
        )

        #expect(abs(percentage - 0.0) < 0.01,
               "Should return 0% for zero tokens")
    }

    @Test func calculateTokenPercentage_withZeroLimit() {
        // Test with zero limit (should return 0 to avoid division by zero)
        let percentage = PercentageCalculator.calculateTokenPercentage(
            tokens: 50000,
            limit: 0
        )

        #expect(abs(percentage - 0.0) < 0.01,
               "Should return 0% for zero limit to avoid division by zero")
    }

    @Test func calculateTokenPercentage_atLimit() {
        // Test when current tokens equals the limit
        let currentTokens = 200000
        let tokenLimit = 200000

        let percentage = PercentageCalculator.calculateTokenPercentage(
            tokens: currentTokens,
            limit: tokenLimit
        )

        #expect(abs(percentage - 100.0) < 0.01,
               "Should return 100% when at token limit")
    }

    @Test func calculateTokenPercentage_overLimit_capped() {
        // Test when current tokens exceeds the limit with capping (default behavior)
        let currentTokens = 250000
        let tokenLimit = 200000

        let percentage = PercentageCalculator.calculateTokenPercentage(
            tokens: currentTokens,
            limit: tokenLimit
        )

        #expect(abs(percentage - 100.0) < 0.01,
               "Should cap at 100% when exceeding token limit")
    }

    @Test func calculateTokenPercentage_overLimit_uncapped() {
        // Test when current tokens exceeds the limit without capping
        let currentTokens = 250000
        let tokenLimit = 200000

        let percentage = PercentageCalculator.calculateTokenPercentage(
            tokens: currentTokens,
            limit: tokenLimit,
            cappedAt100: false
        )

        #expect(abs(percentage - 125.0) < 0.01,
               "Should return over 100% when exceeding token limit and uncapped")
    }

    @Test func calculateTokenPercentage_consistentWithManualCalculation() {
        // Test that our method matches the original manual calculation
        let currentTokens = 150000
        let tokenLimit = 200000

        let calculatorResult = PercentageCalculator.calculateTokenPercentage(
            tokens: currentTokens,
            limit: tokenLimit,
            cappedAt100: false
        )

        let manualResult = (Double(currentTokens) / Double(tokenLimit)) * 100.0

        #expect(abs(calculatorResult - manualResult) < 0.01,
               "PercentageCalculator result should match original manual calculation")
    }
}
