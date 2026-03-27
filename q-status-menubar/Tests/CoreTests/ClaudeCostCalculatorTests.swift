// ABOUTME: Comprehensive tests for ClaudeCostCalculator matching ccusage logic
// Tests cost calculation modes, model pricing, cache tokens, and edge cases

import Testing
import Foundation
@testable import Core

@Suite("ClaudeCostCalculator")
struct ClaudeCostCalculatorTests {

    // MARK: - Basic Cost Calculation Tests

    @Test func costCalculationSonnet() {
        let tokens = ClaudeTokenUsage(
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: 100,
            cache_read_input_tokens: 200
        )

        let cost = ClaudeCostCalculator.calculateCost(
            tokens: tokens,
            model: "claude-3-5-sonnet",
            mode: .calculate,
            existingCost: nil
        )

        // Expected: (1000 * 3/1M) + (500 * 15/1M) + (100 * 3.75/1M) + (200 * 0.3/1M)
        // = 0.003 + 0.0075 + 0.000375 + 0.00006 = 0.010935
        #expect(abs(cost - 0.010935) < 0.000001)
    }

    @Test func costCalculationOpus() {
        let tokens = ClaudeTokenUsage(
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: nil,
            cache_read_input_tokens: nil
        )

        let cost = ClaudeCostCalculator.calculateCost(
            tokens: tokens,
            model: "claude-3-opus",
            mode: .calculate,
            existingCost: nil
        )

        // Expected: (1000 * 15/1M) + (500 * 75/1M) = 0.015 + 0.0375 = 0.0525
        #expect(abs(cost - 0.0525) < 0.000001)
    }

    @Test func costCalculationHaiku() {
        let tokens = ClaudeTokenUsage(
            input_tokens: 10000,
            output_tokens: 5000,
            cache_creation_input_tokens: nil,
            cache_read_input_tokens: nil
        )

        let cost = ClaudeCostCalculator.calculateCost(
            tokens: tokens,
            model: "claude-3-haiku",
            mode: .calculate,
            existingCost: nil
        )

        // Expected: (10000 * 0.25/1M) + (5000 * 1.25/1M) = 0.0025 + 0.00625 = 0.00875
        #expect(abs(cost - 0.00875) < 0.000001)
    }

    @Test func costCalculationNewHaiku() {
        let tokens = ClaudeTokenUsage(
            input_tokens: 10000,
            output_tokens: 5000,
            cache_creation_input_tokens: nil,
            cache_read_input_tokens: nil
        )

        let cost = ClaudeCostCalculator.calculateCost(
            tokens: tokens,
            model: "claude-3-5-haiku",
            mode: .calculate,
            existingCost: nil
        )

        // Expected: (10000 * 1/1M) + (5000 * 5/1M) = 0.01 + 0.025 = 0.035
        #expect(abs(cost - 0.035) < 0.000001)
    }

    // MARK: - Cost Mode Tests

    @Test func costModeDisplay() {
        let tokens = ClaudeTokenUsage(
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: nil,
            cache_read_input_tokens: nil
        )

        // With existing cost
        let cost = ClaudeCostCalculator.calculateCost(
            tokens: tokens,
            model: "claude-3-5-sonnet",
            mode: .display,
            existingCost: 0.123
        )
        #expect(cost == 0.123)

        // Without existing cost
        let costNoExisting = ClaudeCostCalculator.calculateCost(
            tokens: tokens,
            model: "claude-3-5-sonnet",
            mode: .display,
            existingCost: nil
        )
        #expect(costNoExisting == 0.0)
    }

    @Test func costModeAuto() {
        let tokens = ClaudeTokenUsage(
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: nil,
            cache_read_input_tokens: nil
        )

        // With existing cost
        let cost = ClaudeCostCalculator.calculateCost(
            tokens: tokens,
            model: "claude-3-5-sonnet",
            mode: .auto,
            existingCost: 0.123
        )
        #expect(cost == 0.123)

        // Without existing cost - should calculate
        let costCalculated = ClaudeCostCalculator.calculateCost(
            tokens: tokens,
            model: "claude-3-5-sonnet",
            mode: .auto,
            existingCost: nil
        )
        #expect(abs(costCalculated - 0.0105) < 0.000001)

        // With zero existing cost - should calculate
        let costZero = ClaudeCostCalculator.calculateCost(
            tokens: tokens,
            model: "claude-3-5-sonnet",
            mode: .auto,
            existingCost: 0.0
        )
        #expect(abs(costZero - 0.0105) < 0.000001)
    }

    @Test func costModeCalculate() {
        let tokens = ClaudeTokenUsage(
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: nil,
            cache_read_input_tokens: nil
        )

        // Should always calculate, ignoring existing cost
        let cost = ClaudeCostCalculator.calculateCost(
            tokens: tokens,
            model: "claude-3-5-sonnet",
            mode: .calculate,
            existingCost: 999.99
        )
        #expect(abs(cost - 0.0105) < 0.000001)
    }

    // MARK: - Model Name Normalization Tests

    @Test func modelNameWithProviderPrefix() {
        let tokens = ClaudeTokenUsage(
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: nil,
            cache_read_input_tokens: nil
        )

        let prefixes = ["anthropic/", "claude/", "bedrock/", "vertex/"]
        let baseModel = "claude-3-5-sonnet"

        for prefix in prefixes {
            let cost = ClaudeCostCalculator.calculateCost(
                tokens: tokens,
                model: prefix + baseModel,
                mode: .calculate,
                existingCost: nil
            )
            #expect(abs(cost - 0.0105) < 0.000001, "Failed for prefix: \(prefix)")
        }
    }

    @Test func modelNameVariations() {
        let tokens = ClaudeTokenUsage(
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: nil,
            cache_read_input_tokens: nil
        )

        let variations = [
            "claude-3-5-sonnet",
            "claude-3-5-sonnet-20241022",
            "claude-3-5-sonnet-latest",
            "Claude-3-5-Sonnet",  // Case variation
            "CLAUDE-3-5-SONNET"    // Uppercase
        ]

        for model in variations {
            let cost = ClaudeCostCalculator.calculateCost(
                tokens: tokens,
                model: model,
                mode: .calculate,
                existingCost: nil
            )
            #expect(abs(cost - 0.0105) < 0.000001, "Failed for model: \(model)")
        }
    }

    @Test func unknownModelFallback() {
        let tokens = ClaudeTokenUsage(
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: nil,
            cache_read_input_tokens: nil
        )

        let cost = ClaudeCostCalculator.calculateCost(
            tokens: tokens,
            model: "unknown-model-xyz",
            mode: .calculate,
            existingCost: nil
        )

        // Should use default model pricing (sonnet)
        #expect(abs(cost - 0.0105) < 0.000001)
    }

    // MARK: - Cache Token Tests

    @Test func cacheTokenCosts() {
        let tokens = ClaudeTokenUsage(
            input_tokens: 0,
            output_tokens: 0,
            cache_creation_input_tokens: 1000,
            cache_read_input_tokens: 1000
        )

        let cost = ClaudeCostCalculator.calculateCost(
            tokens: tokens,
            model: "claude-3-5-sonnet",
            mode: .calculate,
            existingCost: nil
        )

        // Cache creation: 1000 * 3.75/1M = 0.00375
        // Cache read: 1000 * 0.3/1M = 0.0003
        // Total: 0.00405
        #expect(abs(cost - 0.00405) < 0.000001)
    }

    @Test func mixedTokenTypes() {
        let tokens = ClaudeTokenUsage(
            input_tokens: 1000,
            output_tokens: 2000,
            cache_creation_input_tokens: 500,
            cache_read_input_tokens: 1500
        )

        let cost = ClaudeCostCalculator.calculateCost(
            tokens: tokens,
            model: "claude-3-5-sonnet",
            mode: .calculate,
            existingCost: nil
        )

        // Input: 1000 * 3/1M = 0.003
        // Output: 2000 * 15/1M = 0.03
        // Cache creation: 500 * 3.75/1M = 0.001875
        // Cache read: 1500 * 0.3/1M = 0.00045
        // Total: 0.035325
        #expect(abs(cost - 0.035325) < 0.000001)
    }

    // MARK: - Edge Cases

    @Test func zeroTokens() {
        let tokens = ClaudeTokenUsage(
            input_tokens: 0,
            output_tokens: 0,
            cache_creation_input_tokens: nil,
            cache_read_input_tokens: nil
        )

        let cost = ClaudeCostCalculator.calculateCost(
            tokens: tokens,
            model: "claude-3-5-sonnet",
            mode: .calculate,
            existingCost: nil
        )

        #expect(cost == 0.0)
    }

    @Test func veryLargeTokenCounts() {
        let tokens = ClaudeTokenUsage(
            input_tokens: 1_000_000,
            output_tokens: 500_000,
            cache_creation_input_tokens: 100_000,
            cache_read_input_tokens: 200_000
        )

        let cost = ClaudeCostCalculator.calculateCost(
            tokens: tokens,
            model: "claude-3-5-sonnet",
            mode: .calculate,
            existingCost: nil
        )

        // Input: 1M * 3/1M = 3.0
        // Output: 500K * 15/1M = 7.5
        // Cache creation: 100K * 3.75/1M = 0.375
        // Cache read: 200K * 0.3/1M = 0.06
        // Total: 10.935
        #expect(abs(cost - 10.935) < 0.000001)
    }

    // MARK: - Formatting Tests

    @Test func costFormatting() {
        #expect(ClaudeCostCalculator.formatCost(0.0001) == "$0.0001")
        #expect(ClaudeCostCalculator.formatCost(0.00001) == "$0.0000")
        #expect(ClaudeCostCalculator.formatCost(0.01) == "$0.01")
        #expect(ClaudeCostCalculator.formatCost(1.234567) == "$1.2346")
        #expect(ClaudeCostCalculator.formatCost(1234.56) == "$1,234.56")
    }

    // MARK: - Model Pricing Tests

    @Test func getModelPricing() {
        let pricing = ClaudeCostCalculator.getModelPricing(for: "claude-3-5-sonnet")

        #expect(abs((pricing.inputCostPerToken ?? 0) - 0.000003) < 0.0000000001)
        #expect(abs((pricing.outputCostPerToken ?? 0) - 0.000015) < 0.0000000001)
        #expect(abs((pricing.cacheCreationCostPerToken ?? 0) - 0.00000375) < 0.0000000001)
        #expect(abs((pricing.cacheReadCostPerToken ?? 0) - 0.0000003) < 0.0000000001)
        #expect(pricing.maxTokens == 200_000)
    }

    @Test func availableModels() {
        let models = ClaudeCostCalculator.availableModels()

        #expect(models.contains("claude-3-5-sonnet"))
        #expect(models.contains("claude-3-opus"))
        #expect(models.contains("claude-3-haiku"))
        #expect(models.contains("claude-3-5-haiku"))
        #expect(models.sorted() == models) // Should be sorted
    }

    // MARK: - JSON Loading Tests

    @Test func loadPricingFromJSON() throws {
        // Create a temporary JSON file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_prices.json")
        let testPricing = """
        {
            "test-model": {
                "inputCostPerToken": 0.001,
                "outputCostPerToken": 0.002,
                "cacheCreationCostPerToken": 0.00125,
                "cacheReadCostPerToken": 0.0001,
                "maxTokens": 100000
            }
        }
        """

        try testPricing.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let loadedPricing = try ClaudeCostCalculator.loadPricingFromJSON(at: tempURL)

        #expect(loadedPricing["test-model"] != nil)
        #expect(loadedPricing["test-model"]?.inputCostPerToken == 0.001)
        #expect(loadedPricing["test-model"]?.outputCostPerToken == 0.002)
        #expect(loadedPricing["test-model"]?.maxTokens == 100000)
    }

    // MARK: - Extension Tests

    @Test func tokenUsageExtension() {
        let tokens = ClaudeTokenUsage(
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: nil,
            cache_read_input_tokens: nil
        )

        let cost = tokens.calculateCost(
            model: "claude-3-5-sonnet",
            mode: .calculate,
            existingCost: nil
        )

        #expect(abs(cost - 0.0105) < 0.000001)
    }
}
