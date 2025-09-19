// ABOUTME: Comprehensive tests for ClaudeCostCalculator matching ccusage logic
// Tests cost calculation modes, model pricing, cache tokens, and edge cases

import XCTest
@testable import Core

final class ClaudeCostCalculatorTests: XCTestCase {

    // MARK: - Basic Cost Calculation Tests

    func testCostCalculationSonnet() {
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
        XCTAssertEqual(cost, 0.010935, accuracy: 0.000001)
    }

    func testCostCalculationOpus() {
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
        XCTAssertEqual(cost, 0.0525, accuracy: 0.000001)
    }

    func testCostCalculationHaiku() {
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
        XCTAssertEqual(cost, 0.00875, accuracy: 0.000001)
    }

    func testCostCalculationNewHaiku() {
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
        XCTAssertEqual(cost, 0.035, accuracy: 0.000001)
    }

    // MARK: - Cost Mode Tests

    func testCostModeDisplay() {
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
        XCTAssertEqual(cost, 0.123)

        // Without existing cost
        let costNoExisting = ClaudeCostCalculator.calculateCost(
            tokens: tokens,
            model: "claude-3-5-sonnet",
            mode: .display,
            existingCost: nil
        )
        XCTAssertEqual(costNoExisting, 0.0)
    }

    func testCostModeAuto() {
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
        XCTAssertEqual(cost, 0.123)

        // Without existing cost - should calculate
        let costCalculated = ClaudeCostCalculator.calculateCost(
            tokens: tokens,
            model: "claude-3-5-sonnet",
            mode: .auto,
            existingCost: nil
        )
        XCTAssertEqual(costCalculated, 0.0105, accuracy: 0.000001)

        // With zero existing cost - should calculate
        let costZero = ClaudeCostCalculator.calculateCost(
            tokens: tokens,
            model: "claude-3-5-sonnet",
            mode: .auto,
            existingCost: 0.0
        )
        XCTAssertEqual(costZero, 0.0105, accuracy: 0.000001)
    }

    func testCostModeCalculate() {
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
        XCTAssertEqual(cost, 0.0105, accuracy: 0.000001)
    }

    // MARK: - Model Name Normalization Tests

    func testModelNameWithProviderPrefix() {
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
            XCTAssertEqual(cost, 0.0105, accuracy: 0.000001, "Failed for prefix: \(prefix)")
        }
    }

    func testModelNameVariations() {
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
            XCTAssertEqual(cost, 0.0105, accuracy: 0.000001, "Failed for model: \(model)")
        }
    }

    func testUnknownModelFallback() {
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
        XCTAssertEqual(cost, 0.0105, accuracy: 0.000001)
    }

    // MARK: - Cache Token Tests

    func testCacheTokenCosts() {
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
        XCTAssertEqual(cost, 0.00405, accuracy: 0.000001)
    }

    func testMixedTokenTypes() {
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
        XCTAssertEqual(cost, 0.035325, accuracy: 0.000001)
    }

    // MARK: - Edge Cases

    func testZeroTokens() {
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

        XCTAssertEqual(cost, 0.0)
    }

    func testVeryLargeTokenCounts() {
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
        XCTAssertEqual(cost, 10.935, accuracy: 0.000001)
    }

    // MARK: - Formatting Tests

    func testCostFormatting() {
        XCTAssertEqual(ClaudeCostCalculator.formatCost(0.0001), "$0.0001")
        XCTAssertEqual(ClaudeCostCalculator.formatCost(0.00001), "$0.0000")
        XCTAssertEqual(ClaudeCostCalculator.formatCost(0.01), "$0.01")
        XCTAssertEqual(ClaudeCostCalculator.formatCost(1.234567), "$1.2346")
        XCTAssertEqual(ClaudeCostCalculator.formatCost(1234.56), "$1,234.56")
    }

    // MARK: - Model Pricing Tests

    func testGetModelPricing() {
        let pricing = ClaudeCostCalculator.getModelPricing(for: "claude-3-5-sonnet")

        XCTAssertEqual(pricing.inputCostPerToken ?? 0, 0.000003, accuracy: 0.0000000001)
        XCTAssertEqual(pricing.outputCostPerToken ?? 0, 0.000015, accuracy: 0.0000000001)
        XCTAssertEqual(pricing.cacheCreationCostPerToken ?? 0, 0.00000375, accuracy: 0.0000000001)
        XCTAssertEqual(pricing.cacheReadCostPerToken ?? 0, 0.0000003, accuracy: 0.0000000001)
        XCTAssertEqual(pricing.maxTokens, 200_000)
    }

    func testAvailableModels() {
        let models = ClaudeCostCalculator.availableModels()

        XCTAssertTrue(models.contains("claude-3-5-sonnet"))
        XCTAssertTrue(models.contains("claude-3-opus"))
        XCTAssertTrue(models.contains("claude-3-haiku"))
        XCTAssertTrue(models.contains("claude-3-5-haiku"))
        XCTAssertTrue(models.sorted() == models) // Should be sorted
    }

    // MARK: - JSON Loading Tests

    func testLoadPricingFromJSON() throws {
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

        XCTAssertNotNil(loadedPricing["test-model"])
        XCTAssertEqual(loadedPricing["test-model"]?.inputCostPerToken, 0.001)
        XCTAssertEqual(loadedPricing["test-model"]?.outputCostPerToken, 0.002)
        XCTAssertEqual(loadedPricing["test-model"]?.maxTokens, 100000)
    }

    // MARK: - Extension Tests

    func testTokenUsageExtension() {
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

        XCTAssertEqual(cost, 0.0105, accuracy: 0.000001)
    }

    // MARK: - Performance Tests

    func testPerformanceCalculateCost() {
        let tokens = ClaudeTokenUsage(
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: 100,
            cache_read_input_tokens: 200
        )

        measure {
            for _ in 0..<1000 {
                _ = ClaudeCostCalculator.calculateCost(
                    tokens: tokens,
                    model: "claude-3-5-sonnet",
                    mode: .calculate,
                    existingCost: nil
                )
            }
        }
    }
}