// ABOUTME: Integration test to verify Settings.swift uses centralized PercentageCalculator
// Ensures the Claude token percentage calculation is correctly delegated to PercentageCalculator

import Testing
@testable import Core

@Suite("SettingsIntegration")
struct SettingsIntegrationTests {

    @Test func claudeTokenLimitPercentage_usesPercentageCalculator() {
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
        #expect(abs(settingsResult - calculatorResult) < 0.01,
               "Settings.claudeTokenLimitPercentage should use PercentageCalculator internally")

        // Verify the actual percentage value
        #expect(abs(settingsResult - 75.0) < 0.01,
               "150K tokens out of 200K limit should be 75%")
    }

    @Test func claudeTokenLimitPercentage_behaviorMatchesOriginal() {
        // Ensure the behavior matches the original manual calculation
        let settings = SettingsStore()
        settings.claudeTokenLimit = 200000

        let testCases: [(tokens: Int, expected: Double)] = [
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

            #expect(abs(result - expected) < 0.01,
                   "Failed for \(tokens) tokens: expected \(expected)%, got \(result)%")
            #expect(abs(result - originalCalculation) < 0.01,
                   "Should match original manual calculation for \(tokens) tokens")
        }
    }
}
