// ABOUTME: cost_calculator provides sophisticated cost calculation logic from ccusage
// This module calculates costs for Claude API usage with support for cache tokens and multiple pricing modes

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::Path;

/// Cost calculation modes matching ccusage behavior
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CostMode {
    /// Use pre-calculated costs when available, otherwise calculate from tokens
    Auto,
    /// Always calculate costs from token counts using model pricing
    Calculate,
    /// Always use pre-calculated costs, show 0 for missing costs
    Display,
}

impl Default for CostMode {
    fn default() -> Self {
        CostMode::Auto
    }
}

/// Model pricing information including token costs and limits
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelPricing {
    /// Cost per input token in USD
    #[serde(rename = "input_cost_per_token")]
    pub input_cost_per_token: Option<f64>,
    /// Cost per output token in USD
    #[serde(rename = "output_cost_per_token")]
    pub output_cost_per_token: Option<f64>,
    /// Cost per cache creation token in USD
    #[serde(rename = "cache_creation_input_token_cost")]
    pub cache_creation_cost_per_token: Option<f64>,
    /// Cost per cache read token in USD
    #[serde(rename = "cache_read_input_token_cost")]
    pub cache_read_cost_per_token: Option<f64>,
    /// Maximum total tokens for the model
    pub max_tokens: Option<usize>,
    /// Maximum input tokens for the model
    pub max_input_tokens: Option<usize>,
    /// Maximum output tokens for the model
    pub max_output_tokens: Option<usize>,
}

impl ModelPricing {
    /// Create pricing from cost per million tokens (common format)
    pub fn from_million_tokens(
        input_cost_per_million: f64,
        output_cost_per_million: f64,
        cache_creation_multiplier: Option<f64>,
        cache_read_multiplier: Option<f64>,
        max_tokens: Option<usize>,
    ) -> Self {
        let input_per_token = input_cost_per_million / 1_000_000.0;
        let cache_creation_multiplier = cache_creation_multiplier.unwrap_or(1.25); // 25% more
        let cache_read_multiplier = cache_read_multiplier.unwrap_or(0.10); // 90% discount

        Self {
            input_cost_per_token: Some(input_per_token),
            output_cost_per_token: Some(output_cost_per_million / 1_000_000.0),
            cache_creation_cost_per_token: Some(input_per_token * cache_creation_multiplier),
            cache_read_cost_per_token: Some(input_per_token * cache_read_multiplier),
            max_tokens,
            max_input_tokens: None,
            max_output_tokens: None,
        }
    }
}

/// Token usage structure compatible with Claude JSONL format
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TokenUsage {
    pub input_tokens: u32,
    pub output_tokens: u32,
    pub cache_creation_input_tokens: Option<u32>,
    pub cache_read_input_tokens: Option<u32>,
}

impl TokenUsage {
    /// Calculate total tokens including cache tokens
    pub fn total(&self) -> u64 {
        self.input_tokens as u64
            + self.output_tokens as u64
            + self.cache_creation_input_tokens.unwrap_or(0) as u64
            + self.cache_read_input_tokens.unwrap_or(0) as u64
    }
}

/// Main cost calculator implementing ccusage logic
pub struct CostCalculator {
    /// Model pricing data
    pricing_data: HashMap<String, ModelPricing>,
    /// Default model for fallback
    default_model: String,
}

impl Default for CostCalculator {
    fn default() -> Self {
        Self::new()
    }
}

impl CostCalculator {
    /// Create a new cost calculator with default pricing
    pub fn new() -> Self {
        let mut pricing_data = HashMap::new();

        // Claude 3.5 Sonnet variants
        pricing_data.insert(
            "claude-3-5-sonnet".to_string(),
            ModelPricing::from_million_tokens(3.0, 15.0, None, None, Some(200_000))
        );
        pricing_data.insert(
            "claude-3-5-sonnet-20241022".to_string(),
            ModelPricing::from_million_tokens(3.0, 15.0, None, None, Some(200_000))
        );
        pricing_data.insert(
            "claude-3-5-sonnet-latest".to_string(),
            ModelPricing::from_million_tokens(3.0, 15.0, None, None, Some(200_000))
        );

        // Claude 3 Opus variants
        pricing_data.insert(
            "claude-3-opus".to_string(),
            ModelPricing::from_million_tokens(15.0, 75.0, None, None, Some(200_000))
        );
        pricing_data.insert(
            "claude-3-opus-20240229".to_string(),
            ModelPricing::from_million_tokens(15.0, 75.0, None, None, Some(200_000))
        );
        pricing_data.insert(
            "claude-3-opus-latest".to_string(),
            ModelPricing::from_million_tokens(15.0, 75.0, None, None, Some(200_000))
        );

        // Claude 3 Haiku variants
        pricing_data.insert(
            "claude-3-haiku".to_string(),
            ModelPricing::from_million_tokens(0.25, 1.25, None, None, Some(200_000))
        );
        pricing_data.insert(
            "claude-3-haiku-20240307".to_string(),
            ModelPricing::from_million_tokens(0.25, 1.25, None, None, Some(200_000))
        );
        pricing_data.insert(
            "claude-3-haiku-latest".to_string(),
            ModelPricing::from_million_tokens(0.25, 1.25, None, None, Some(200_000))
        );

        // Claude 3.5 Haiku (newer, different pricing)
        pricing_data.insert(
            "claude-3-5-haiku".to_string(),
            ModelPricing::from_million_tokens(1.0, 5.0, None, None, Some(200_000))
        );
        pricing_data.insert(
            "claude-3-5-haiku-20241022".to_string(),
            ModelPricing::from_million_tokens(1.0, 5.0, None, None, Some(200_000))
        );

        // Legacy models
        pricing_data.insert(
            "claude-2.1".to_string(),
            ModelPricing::from_million_tokens(8.0, 24.0, None, None, Some(200_000))
        );
        pricing_data.insert(
            "claude-2.0".to_string(),
            ModelPricing::from_million_tokens(8.0, 24.0, None, None, Some(100_000))
        );
        pricing_data.insert(
            "claude-instant-1.2".to_string(),
            ModelPricing::from_million_tokens(0.8, 2.4, None, None, Some(100_000))
        );

        Self {
            pricing_data,
            default_model: "claude-3-5-sonnet-20241022".to_string(),
        }
    }

    /// Load pricing from JSON file
    pub fn load_from_json<P: AsRef<Path>>(path: P) -> Result<Self, Box<dyn std::error::Error>> {
        let content = fs::read_to_string(path)?;
        let pricing_data: HashMap<String, ModelPricing> = serde_json::from_str(&content)?;

        Ok(Self {
            pricing_data,
            default_model: "claude-3-5-sonnet-20241022".to_string(),
        })
    }

    /// Calculate cost based on tokens and model with specified mode
    pub fn calculate_cost(
        &self,
        tokens: &TokenUsage,
        model: &str,
        mode: CostMode,
        existing_cost: Option<f64>,
    ) -> f64 {
        match mode {
            CostMode::Display => {
                // Always use pre-calculated cost, 0 if not available
                existing_cost.unwrap_or(0.0)
            }
            CostMode::Calculate => {
                // Always calculate from tokens
                self.calculate_from_tokens(tokens, model)
            }
            CostMode::Auto => {
                // Use existing cost if available and > 0, otherwise calculate
                if let Some(cost) = existing_cost {
                    if cost > 0.0 {
                        return cost;
                    }
                }
                self.calculate_from_tokens(tokens, model)
            }
        }
    }

    /// Calculate cost from token counts and model pricing
    fn calculate_from_tokens(&self, tokens: &TokenUsage, model: &str) -> f64 {
        let pricing = self.get_pricing(model);
        self.calculate_cost_from_pricing(tokens, pricing)
    }

    /// Calculate cost using specific pricing information (matching ccusage logic)
    fn calculate_cost_from_pricing(&self, tokens: &TokenUsage, pricing: &ModelPricing) -> f64 {
        let mut cost = 0.0;

        // Input tokens cost
        if let Some(input_cost) = pricing.input_cost_per_token {
            cost += tokens.input_tokens as f64 * input_cost;
        }

        // Output tokens cost
        if let Some(output_cost) = pricing.output_cost_per_token {
            cost += tokens.output_tokens as f64 * output_cost;
        }

        // Cache creation tokens cost
        if let Some(cache_creation_tokens) = tokens.cache_creation_input_tokens {
            if let Some(cache_creation_cost) = pricing.cache_creation_cost_per_token {
                cost += cache_creation_tokens as f64 * cache_creation_cost;
            }
        }

        // Cache read tokens cost
        if let Some(cache_read_tokens) = tokens.cache_read_input_tokens {
            if let Some(cache_read_cost) = pricing.cache_read_cost_per_token {
                cost += cache_read_tokens as f64 * cache_read_cost;
            }
        }

        cost
    }

    /// Get pricing for a model, handling name variations and provider prefixes
    fn get_pricing(&self, model: &str) -> &ModelPricing {
        // Normalize model name
        let normalized = self.normalize_model_name(model);

        // Try exact match first
        if let Some(pricing) = self.pricing_data.get(&normalized) {
            return pricing;
        }

        // Try fuzzy matching
        if let Some(pricing) = self.fuzzy_match_model(&normalized) {
            return pricing;
        }

        // Fallback to default model
        self.pricing_data.get(&self.default_model)
            .unwrap_or(&ModelPricing {
                input_cost_per_token: Some(0.000003),
                output_cost_per_token: Some(0.000015),
                cache_creation_cost_per_token: Some(0.00000375),
                cache_read_cost_per_token: Some(0.0000003),
                max_tokens: Some(200_000),
                max_input_tokens: None,
                max_output_tokens: None,
            })
    }

    /// Normalize model name by removing provider prefixes and standardizing format
    fn normalize_model_name(&self, model: &str) -> String {
        let mut normalized = model.to_lowercase();

        // Remove common provider prefixes
        let prefixes = ["anthropic/", "claude/", "bedrock/", "vertex/"];
        for prefix in prefixes {
            if normalized.starts_with(prefix) {
                normalized = normalized[prefix.len()..].to_string();
            }
        }

        // Handle special cases
        normalized = normalized
            .replace("claude-3.5-", "claude-3-5-")
            .replace("claude3.5", "claude-3-5")
            .replace("claude3-", "claude-3-");

        normalized
    }

    /// Fuzzy match model name to find best pricing match
    fn fuzzy_match_model(&self, model: &str) -> Option<&ModelPricing> {
        // Check for model family matches
        if model.contains("opus") {
            self.pricing_data.get("claude-3-opus")
        } else if model.contains("sonnet") {
            if model.contains("3-5") || model.contains("3.5") {
                self.pricing_data.get("claude-3-5-sonnet")
            } else {
                self.pricing_data.get("claude-3-5-sonnet") // Default to 3.5
            }
        } else if model.contains("haiku") {
            if model.contains("3-5") || model.contains("3.5") {
                self.pricing_data.get("claude-3-5-haiku")
            } else {
                self.pricing_data.get("claude-3-haiku")
            }
        } else if model.contains("instant") {
            self.pricing_data.get("claude-instant-1.2")
        } else if model.contains("claude-2") {
            self.pricing_data.get("claude-2.1")
        } else {
            None
        }
    }

    /// Get model pricing information for a specific model
    pub fn get_model_pricing(&self, model: &str) -> ModelPricing {
        self.get_pricing(model).clone()
    }

    /// Get all available model names
    pub fn available_models(&self) -> Vec<String> {
        let mut models: Vec<String> = self.pricing_data.keys().cloned().collect();
        models.sort();
        models
    }

    /// Format cost as USD string
    pub fn format_cost(cost: f64) -> String {
        if cost < 0.01 {
            format!("${:.4}", cost)
        } else {
            format!("${:.2}", cost)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cost_calculation_sonnet() {
        let calculator = CostCalculator::new();
        let tokens = TokenUsage {
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: Some(100),
            cache_read_input_tokens: Some(200),
        };

        let cost = calculator.calculate_cost(
            &tokens,
            "claude-3-5-sonnet",
            CostMode::Calculate,
            None
        );

        // Expected: (1000 * 3/1M) + (500 * 15/1M) + (100 * 3.75/1M) + (200 * 0.3/1M)
        // = 0.003 + 0.0075 + 0.000375 + 0.00006 = 0.010935
        assert!((cost - 0.010935).abs() < 0.000001);
    }

    #[test]
    fn test_cost_calculation_opus() {
        let calculator = CostCalculator::new();
        let tokens = TokenUsage {
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: None,
            cache_read_input_tokens: None,
        };

        let cost = calculator.calculate_cost(
            &tokens,
            "claude-3-opus",
            CostMode::Calculate,
            None
        );

        // Expected: (1000 * 15/1M) + (500 * 75/1M) = 0.015 + 0.0375 = 0.0525
        assert!((cost - 0.0525).abs() < 0.000001);
    }

    #[test]
    fn test_cost_calculation_haiku() {
        let calculator = CostCalculator::new();
        let tokens = TokenUsage {
            input_tokens: 10000,
            output_tokens: 5000,
            cache_creation_input_tokens: None,
            cache_read_input_tokens: None,
        };

        let cost = calculator.calculate_cost(
            &tokens,
            "claude-3-haiku",
            CostMode::Calculate,
            None
        );

        // Expected: (10000 * 0.25/1M) + (5000 * 1.25/1M) = 0.0025 + 0.00625 = 0.00875
        assert!((cost - 0.00875).abs() < 0.000001);
    }

    #[test]
    fn test_cost_mode_display() {
        let calculator = CostCalculator::new();
        let tokens = TokenUsage {
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: None,
            cache_read_input_tokens: None,
        };

        let cost = calculator.calculate_cost(
            &tokens,
            "claude-3-5-sonnet",
            CostMode::Display,
            Some(0.123)
        );

        assert_eq!(cost, 0.123);

        let cost_no_existing = calculator.calculate_cost(
            &tokens,
            "claude-3-5-sonnet",
            CostMode::Display,
            None
        );

        assert_eq!(cost_no_existing, 0.0);
    }

    #[test]
    fn test_cost_mode_auto() {
        let calculator = CostCalculator::new();
        let tokens = TokenUsage {
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: None,
            cache_read_input_tokens: None,
        };

        // With existing cost
        let cost = calculator.calculate_cost(
            &tokens,
            "claude-3-5-sonnet",
            CostMode::Auto,
            Some(0.123)
        );
        assert_eq!(cost, 0.123);

        // Without existing cost
        let cost_calculated = calculator.calculate_cost(
            &tokens,
            "claude-3-5-sonnet",
            CostMode::Auto,
            None
        );
        assert!((cost_calculated - 0.0105).abs() < 0.000001);
    }

    #[test]
    fn test_model_name_normalization() {
        let calculator = CostCalculator::new();
        let tokens = TokenUsage {
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: None,
            cache_read_input_tokens: None,
        };

        // Test with provider prefix
        let cost1 = calculator.calculate_cost(
            &tokens,
            "anthropic/claude-3-5-sonnet",
            CostMode::Calculate,
            None
        );

        let cost2 = calculator.calculate_cost(
            &tokens,
            "claude-3-5-sonnet",
            CostMode::Calculate,
            None
        );

        assert_eq!(cost1, cost2);
    }

    #[test]
    fn test_unknown_model_fallback() {
        let calculator = CostCalculator::new();
        let tokens = TokenUsage {
            input_tokens: 1000,
            output_tokens: 500,
            cache_creation_input_tokens: None,
            cache_read_input_tokens: None,
        };

        let cost = calculator.calculate_cost(
            &tokens,
            "unknown-model-xyz",
            CostMode::Calculate,
            None
        );

        // Should use default model pricing (sonnet)
        assert!((cost - 0.0105).abs() < 0.000001);
    }

    #[test]
    fn test_cache_token_costs() {
        let calculator = CostCalculator::new();
        let tokens = TokenUsage {
            input_tokens: 0,
            output_tokens: 0,
            cache_creation_input_tokens: Some(1000),
            cache_read_input_tokens: Some(1000),
        };

        let cost = calculator.calculate_cost(
            &tokens,
            "claude-3-5-sonnet",
            CostMode::Calculate,
            None
        );

        // Cache creation: 1000 * 3.75/1M = 0.00375
        // Cache read: 1000 * 0.3/1M = 0.0003
        // Total: 0.00405
        assert!((cost - 0.00405).abs() < 0.000001);
    }

    #[test]
    fn test_format_cost() {
        assert_eq!(CostCalculator::format_cost(0.0001), "$0.0001");
        assert_eq!(CostCalculator::format_cost(0.01), "$0.01");
        assert_eq!(CostCalculator::format_cost(1.234), "$1.23");
        assert_eq!(CostCalculator::format_cost(1234.56), "$1234.56");
    }
}