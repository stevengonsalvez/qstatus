// ABOUTME: ClaudeCostCalculator provides sophisticated cost calculation logic from ccusage
// This module calculates costs for Claude API usage with support for cache tokens and multiple pricing modes

import Foundation

// MARK: - Cost Calculation Mode

/// Cost calculation modes matching ccusage behavior
public enum CostMode: String, CaseIterable, Codable {
    /// Use pre-calculated costs when available, otherwise calculate from tokens
    case auto = "auto"
    /// Always calculate costs from token counts using model pricing
    case calculate = "calculate"
    /// Always use pre-calculated costs, show 0 for missing costs
    case display = "display"
}

// MARK: - Model Pricing Structure

/// Model pricing information including token costs and limits
public struct ModelPricing: Codable {
    /// Cost per input token in USD
    public let inputCostPerToken: Double?
    /// Cost per output token in USD
    public let outputCostPerToken: Double?
    /// Cost per cache creation token in USD
    public let cacheCreationCostPerToken: Double?
    /// Cost per cache read token in USD
    public let cacheReadCostPerToken: Double?
    /// Maximum total tokens for the model
    public let maxTokens: Int?
    /// Maximum input tokens for the model
    public let maxInputTokens: Int?
    /// Maximum output tokens for the model
    public let maxOutputTokens: Int?

    /// Initialize with individual cost values
    public init(
        inputCostPerToken: Double? = nil,
        outputCostPerToken: Double? = nil,
        cacheCreationCostPerToken: Double? = nil,
        cacheReadCostPerToken: Double? = nil,
        maxTokens: Int? = nil,
        maxInputTokens: Int? = nil,
        maxOutputTokens: Int? = nil
    ) {
        self.inputCostPerToken = inputCostPerToken
        self.outputCostPerToken = outputCostPerToken
        self.cacheCreationCostPerToken = cacheCreationCostPerToken
        self.cacheReadCostPerToken = cacheReadCostPerToken
        self.maxTokens = maxTokens
        self.maxInputTokens = maxInputTokens
        self.maxOutputTokens = maxOutputTokens
    }

    /// Initialize from cost per million tokens (common format)
    public static func fromMillionTokens(
        inputCostPerMillion: Double,
        outputCostPerMillion: Double,
        cacheCreationMultiplier: Double = 1.25, // 25% more than input
        cacheReadMultiplier: Double = 0.10, // 90% discount from input
        maxTokens: Int? = nil,
        maxInputTokens: Int? = nil,
        maxOutputTokens: Int? = nil
    ) -> ModelPricing {
        let inputPerToken = inputCostPerMillion / 1_000_000.0
        return ModelPricing(
            inputCostPerToken: inputPerToken,
            outputCostPerToken: outputCostPerMillion / 1_000_000.0,
            cacheCreationCostPerToken: inputPerToken * cacheCreationMultiplier,
            cacheReadCostPerToken: inputPerToken * cacheReadMultiplier,
            maxTokens: maxTokens,
            maxInputTokens: maxInputTokens,
            maxOutputTokens: maxOutputTokens
        )
    }
}

// MARK: - Claude Cost Calculator

/// Main cost calculator implementing ccusage logic
public struct ClaudeCostCalculator {

    // MARK: - Properties

    /// Model pricing data from LiteLLM (prices per million tokens)
    private static let modelPricing: [String: ModelPricing] = [
        // Claude 3.5 Sonnet variants
        "claude-3-5-sonnet": ModelPricing.fromMillionTokens(
            inputCostPerMillion: 3.0,
            outputCostPerMillion: 15.0,
            maxTokens: 200_000
        ),
        "claude-3-5-sonnet-20241022": ModelPricing.fromMillionTokens(
            inputCostPerMillion: 3.0,
            outputCostPerMillion: 15.0,
            maxTokens: 200_000
        ),
        "claude-3-5-sonnet-latest": ModelPricing.fromMillionTokens(
            inputCostPerMillion: 3.0,
            outputCostPerMillion: 15.0,
            maxTokens: 200_000
        ),

        // Claude 3 Opus variants
        "claude-3-opus": ModelPricing.fromMillionTokens(
            inputCostPerMillion: 15.0,
            outputCostPerMillion: 75.0,
            maxTokens: 200_000
        ),
        "claude-3-opus-20240229": ModelPricing.fromMillionTokens(
            inputCostPerMillion: 15.0,
            outputCostPerMillion: 75.0,
            maxTokens: 200_000
        ),
        "claude-3-opus-latest": ModelPricing.fromMillionTokens(
            inputCostPerMillion: 15.0,
            outputCostPerMillion: 75.0,
            maxTokens: 200_000
        ),

        // Claude 3 Haiku variants
        "claude-3-haiku": ModelPricing.fromMillionTokens(
            inputCostPerMillion: 0.25,
            outputCostPerMillion: 1.25,
            maxTokens: 200_000
        ),
        "claude-3-haiku-20240307": ModelPricing.fromMillionTokens(
            inputCostPerMillion: 0.25,
            outputCostPerMillion: 1.25,
            maxTokens: 200_000
        ),
        "claude-3-haiku-latest": ModelPricing.fromMillionTokens(
            inputCostPerMillion: 0.25,
            outputCostPerMillion: 1.25,
            maxTokens: 200_000
        ),

        // Claude 3.5 Haiku (newer, different pricing)
        "claude-3-5-haiku": ModelPricing.fromMillionTokens(
            inputCostPerMillion: 1.0,
            outputCostPerMillion: 5.0,
            maxTokens: 200_000
        ),
        "claude-3-5-haiku-20241022": ModelPricing.fromMillionTokens(
            inputCostPerMillion: 1.0,
            outputCostPerMillion: 5.0,
            maxTokens: 200_000
        ),

        // Claude 4 Opus (newer generation)
        "claude-opus-4-1-20250805": ModelPricing.fromMillionTokens(
            inputCostPerMillion: 15.0,  // Same as Claude 3 Opus for now
            outputCostPerMillion: 75.0,
            maxTokens: 200_000
        ),
        "claude-opus-4-1": ModelPricing.fromMillionTokens(
            inputCostPerMillion: 15.0,
            outputCostPerMillion: 75.0,
            maxTokens: 200_000
        ),

        // Claude 4 Sonnet (newer generation)
        "claude-sonnet-4-20250514": ModelPricing.fromMillionTokens(
            inputCostPerMillion: 3.0,  // Same as Claude 3.5 Sonnet for now
            outputCostPerMillion: 15.0,
            maxTokens: 200_000
        ),
        "claude-sonnet-4": ModelPricing.fromMillionTokens(
            inputCostPerMillion: 3.0,
            outputCostPerMillion: 15.0,
            maxTokens: 200_000
        ),

        // Legacy/fallback
        "claude-2.1": ModelPricing.fromMillionTokens(
            inputCostPerMillion: 8.0,
            outputCostPerMillion: 24.0,
            maxTokens: 200_000
        ),
        "claude-2.0": ModelPricing.fromMillionTokens(
            inputCostPerMillion: 8.0,
            outputCostPerMillion: 24.0,
            maxTokens: 100_000
        ),
        "claude-instant-1.2": ModelPricing.fromMillionTokens(
            inputCostPerMillion: 0.8,
            outputCostPerMillion: 2.4,
            maxTokens: 100_000
        )
    ]

    /// Default model for fallback pricing
    private static let defaultModel = "claude-3-5-sonnet-20241022"

    // MARK: - Public Methods

    /// Calculate cost based on tokens and model with specified mode
    /// - Parameters:
    ///   - tokens: Token usage breakdown
    ///   - model: Model name (can include provider prefix)
    ///   - mode: Cost calculation mode
    ///   - existingCost: Pre-calculated cost from JSONL (for auto/display modes)
    /// - Returns: Calculated cost in USD
    public static func calculateCost(
        tokens: ClaudeTokenUsage,
        model: String,
        mode: CostMode = .auto,
        existingCost: Double? = nil
    ) -> Double {
        switch mode {
        case .display:
            // Always use pre-calculated cost, 0 if not available
            return existingCost ?? 0.0

        case .calculate:
            // Always calculate from tokens
            return calculateFromTokens(tokens: tokens, model: model)

        case .auto:
            // Use existing cost if available, otherwise calculate
            if let cost = existingCost, cost > 0 {
                return cost
            }
            return calculateFromTokens(tokens: tokens, model: model)
        }
    }

    /// Calculate cost from token counts and model pricing
    private static func calculateFromTokens(tokens: ClaudeTokenUsage, model: String) -> Double {
        let pricing = getPricing(for: model)
        return calculateCostFromPricing(tokens: tokens, pricing: pricing)
    }

    /// Calculate cost using specific pricing information (matching ccusage logic)
    private static func calculateCostFromPricing(
        tokens: ClaudeTokenUsage,
        pricing: ModelPricing
    ) -> Double {
        var cost: Double = 0

        // Input tokens cost
        if let inputCost = pricing.inputCostPerToken {
            cost += Double(tokens.input_tokens) * inputCost
        }

        // Output tokens cost
        if let outputCost = pricing.outputCostPerToken {
            cost += Double(tokens.output_tokens) * outputCost
        }

        // Cache creation tokens cost
        if let cacheCreationTokens = tokens.cache_creation_input_tokens,
           let cacheCreationCost = pricing.cacheCreationCostPerToken {
            cost += Double(cacheCreationTokens) * cacheCreationCost
        }

        // Cache read tokens cost
        if let cacheReadTokens = tokens.cache_read_input_tokens,
           let cacheReadCost = pricing.cacheReadCostPerToken {
            cost += Double(cacheReadTokens) * cacheReadCost
        }

        return cost
    }

    // MARK: - Model Name Handling

    /// Get pricing for a model, handling name variations and provider prefixes
    private static func getPricing(for model: String) -> ModelPricing {
        // Normalize model name
        let normalizedModel = normalizeModelName(model)

        // Try exact match first
        if let pricing = modelPricing[normalizedModel] {
            return pricing
        }

        // Try fuzzy matching
        if let pricing = fuzzyMatchModel(normalizedModel) {
            return pricing
        }

        // Fallback to default model
        return modelPricing[defaultModel] ?? ModelPricing()
    }

    /// Normalize model name by removing provider prefixes and standardizing format
    private static func normalizeModelName(_ model: String) -> String {
        var normalized = model.lowercased()

        // Remove common provider prefixes
        let prefixes = ["anthropic/", "claude/", "bedrock/", "vertex/"]
        for prefix in prefixes {
            if normalized.hasPrefix(prefix) {
                normalized = String(normalized.dropFirst(prefix.count))
            }
        }

        // Handle special cases
        normalized = normalized
            .replacingOccurrences(of: "claude-3.5-", with: "claude-3-5-")
            .replacingOccurrences(of: "claude3.5", with: "claude-3-5")
            .replacingOccurrences(of: "claude3-", with: "claude-3-")

        return normalized
    }

    /// Fuzzy match model name to find best pricing match
    private static func fuzzyMatchModel(_ model: String) -> ModelPricing? {
        // Check for model family matches
        if model.contains("opus") {
            // Check for Claude 4 Opus
            if model.contains("4-1") || model.contains("opus-4") {
                return modelPricing["claude-opus-4-1"]
            }
            return modelPricing["claude-3-opus"]
        } else if model.contains("sonnet") {
            // Check for Claude 4 Sonnet
            if model.contains("sonnet-4") {
                return modelPricing["claude-sonnet-4"]
            }
            // Check for Claude 3.5 Sonnet
            if model.contains("3-5") || model.contains("3.5") {
                return modelPricing["claude-3-5-sonnet"]
            }
            return modelPricing["claude-3-5-sonnet"] // Default to 3.5
        } else if model.contains("haiku") {
            if model.contains("3-5") || model.contains("3.5") {
                return modelPricing["claude-3-5-haiku"]
            }
            return modelPricing["claude-3-haiku"]
        } else if model.contains("instant") {
            return modelPricing["claude-instant-1.2"]
        } else if model.contains("claude-2") {
            return modelPricing["claude-2.1"]
        }

        return nil
    }

    // MARK: - Utility Methods

    /// Get model pricing information for a specific model
    public static func getModelPricing(for model: String) -> ModelPricing {
        return getPricing(for: model)
    }

    /// Get all available model names
    public static func availableModels() -> [String] {
        return Array(modelPricing.keys).sorted()
    }

    /// Format cost as USD string
    public static func formatCost(_ cost: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4

        // For very small values, always show 4 decimal places
        if cost < 0.01 && cost > 0 {
            formatter.minimumFractionDigits = 4
        }

        return formatter.string(from: NSNumber(value: cost)) ?? "$0.00"
    }

    /// Load custom pricing from JSON file
    public static func loadPricingFromJSON(at url: URL) throws -> [String: ModelPricing] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([String: ModelPricing].self, from: data)
    }
}

// MARK: - Extensions

extension ClaudeTokenUsage {
    /// Calculate total cost for this token usage
    public func calculateCost(
        model: String,
        mode: CostMode = .auto,
        existingCost: Double? = nil
    ) -> Double {
        return ClaudeCostCalculator.calculateCost(
            tokens: self,
            model: model,
            mode: mode,
            existingCost: existingCost
        )
    }
}