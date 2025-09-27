// ABOUTME: Integration test to verify Settings.swift uses centralized PercentageCalculator
// Ensures the Claude token percentage calculation is correctly delegated to PercentageCalculator

import XCTest
@testable import Core

final class SettingsIntegrationTest: XCTestCase {

    func testClaudeTokenLimitPercentage_usesPercentageCalculator() {
        // Verify that Settings.claudeTokenLimitPercentage uses PercentageCalculator
        let settings = SettingsStore()
        settings.claudeTokenLimit = 200000

        let currentTokens = 150000

        // Get result from Settings
        let settingsResult = settings.claudeTokenLimitPercentage(currentTokens: currentTokens)

        // Get result directly from PercentageCalculator
        let calculatorResult = PercentageCalculator.calculateTokenPercentage(
            tokens: currentTokens,
            limit: settings.claudeTokenLimit,
            cappedAt100: false
        )

        // They should be identical
        XCTAssertEqual(settingsResult, calculatorResult, accuracy: 0.01,
                      "Settings.claudeTokenLimitPercentage should use PercentageCalculator internally")

        // Verify the actual percentage value
        XCTAssertEqual(settingsResult, 75.0, accuracy: 0.01,
                      "150K tokens out of 200K limit should be 75%")
    }

    func testClaudeTokenLimitPercentage_behaviorMatchesOriginal() {
        // Ensure the behavior matches the original manual calculation
        let settings = SettingsStore()
        settings.claudeTokenLimit = 200000

        let testCases = [
            (tokens: 0, expected: 0.0),
            (tokens: 50000, expected: 25.0),
            (tokens: 100000, expected: 50.0),
            (tokens: 150000, expected: 75.0),
            (tokens: 200000, expected: 100.0),
            (tokens: 250000, expected: 125.0)  // Original calculation allowed over 100%
        ]

        for (tokens, expected) in testCases {
            let result = settings.claudeTokenLimitPercentage(currentTokens: tokens)
            let originalCalculation = (Double(tokens) / Double(settings.claudeTokenLimit)) * 100.0

            XCTAssertEqual(result, expected, accuracy: 0.01,
                          "Failed for \(tokens) tokens: expected \(expected)%, got \(result)%")
            XCTAssertEqual(result, originalCalculation, accuracy: 0.01,
                          "Should match original manual calculation for \(tokens) tokens")
        }
    }
}