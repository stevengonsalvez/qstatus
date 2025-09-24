// ABOUTME: PercentageCalculator provides a single source of truth for all percentage calculations
// This eliminates duplicate logic and ensures consistent calculations across the entire app

import Foundation

/// Centralized calculator for all percentage calculations in the app
/// Ensures consistent logic between status bar, dropdown, and any other UI components
public struct PercentageCalculator {

    // MARK: - Constants

    /// Cost baseline for comparing block costs (reasonable daily budget)
    private static let costBaseline: Double = 140.0

    /// Default token baseline when no personal max is available
    private static let defaultTokenBaseline: Int = 10_000_000

    // MARK: - Public Methods

    /// Calculate the critical percentage (maximum of token and cost percentages)
    /// This is the primary percentage shown in the UI
    public static func calculateCriticalPercentage(
        activeSession: ActiveSessionData?,
        maxTokensFromPreviousBlocks: Int?,
        monthlyData: (cost: Double, limit: Double)? = nil
    ) -> Double {
        // Check if we have an active session with a block
        if let activeSession = activeSession,
           let block = activeSession.currentBlock {
            // Active block - calculate both percentages and return the higher one
            let tokenPct = calculateTokenPercentage(
                tokens: block.tokenCounts.totalTokens,
                maxFromPrevious: maxTokensFromPreviousBlocks
            )
            let costPct = calculateCostPercentage(
                cost: block.costUSD,
                useBlockBaseline: true
            )
            return max(tokenPct, costPct)
        } else if let activeSession = activeSession {
            // Have active session but no block - use session data
            let tokenPct = calculateTokenPercentage(
                tokens: activeSession.tokens,
                maxFromPrevious: maxTokensFromPreviousBlocks
            )
            let costPct = calculateCostPercentage(
                cost: activeSession.cost,
                useBlockBaseline: true
            )
            return max(tokenPct, costPct)
        } else if let monthlyData = monthlyData, monthlyData.limit > 0 {
            // No active session - use monthly data
            return calculateCostPercentage(
                cost: monthlyData.cost,
                useBlockBaseline: false,
                monthlyLimit: monthlyData.limit
            )
        }

        return 0
    }

    /// Calculate token usage percentage
    public static func calculateTokenPercentage(
        tokens: Int,
        maxFromPrevious: Int?
    ) -> Double {
        let baseline = Double(maxFromPrevious ?? defaultTokenBaseline)
        guard baseline > 0 else { return 0 }
        return min(100.0, (Double(tokens) / baseline) * 100.0)
    }

    /// Calculate token percentage against a specific limit
    /// Used for context window calculations and monthly token limits
    public static func calculateTokenPercentage(
        tokens: Int,
        limit: Int,
        cappedAt100: Bool = true
    ) -> Double {
        guard limit > 0 else { return 0 }
        let percentage = (Double(tokens) / Double(limit)) * 100.0
        return cappedAt100 ? min(100.0, percentage) : percentage
    }

    /// Calculate cost usage percentage
    public static func calculateCostPercentage(
        cost: Double,
        useBlockBaseline: Bool,
        monthlyLimit: Double? = nil
    ) -> Double {
        if useBlockBaseline {
            // Use $140 baseline for blocks
            return min(100.0, (cost / costBaseline) * 100.0)
        } else if let limit = monthlyLimit, limit > 0 {
            // Use monthly limit for non-block calculations
            return min(100.0, (cost / limit) * 100.0)
        }
        return 0
    }

    /// Calculate session percentage for SessionSummary objects
    /// This replaces the old contextTokens/200K calculation
    public static func calculateSessionPercentage(
        session: ClaudeSession,
        currentBlock: SessionBlock?,
        maxTokensFromPreviousBlocks: Int?
    ) -> Double {
        if let block = currentBlock {
            // Use block-based calculation
            let tokenPct = calculateTokenPercentage(
                tokens: block.tokenCounts.totalTokens,
                maxFromPrevious: maxTokensFromPreviousBlocks
            )
            let costPct = calculateCostPercentage(
                cost: block.costUSD,
                useBlockBaseline: true
            )
            return max(tokenPct, costPct)
        } else {
            // Fallback to session totals
            let tokenPct = calculateTokenPercentage(
                tokens: session.totalTokens,
                maxFromPrevious: maxTokensFromPreviousBlocks
            )
            // For sessions without blocks, use a more conservative calculation
            // This prevents showing 100% for old sessions
            return tokenPct
        }
    }

    /// Determine which metric is critical (tokens or cost)
    public static func getCriticalMetric(
        activeSession: ActiveSessionData?,
        maxTokensFromPreviousBlocks: Int?
    ) -> (type: String, isTokenCritical: Bool) {
        guard let activeSession = activeSession,
              let block = activeSession.currentBlock else {
            return ("Cost", false)
        }

        let tokenPct = calculateTokenPercentage(
            tokens: block.tokenCounts.totalTokens,
            maxFromPrevious: maxTokensFromPreviousBlocks
        )
        let costPct = calculateCostPercentage(
            cost: block.costUSD,
            useBlockBaseline: true
        )

        if tokenPct >= costPct {
            return ("Tokens", true)
        } else {
            return ("Cost", false)
        }
    }

    /// Calculate message quota percentage
    /// Used for displaying message usage against the 5000 message quota
    public static func calculateMessageQuotaPercentage(
        messages: Int,
        quota: Int = 5000
    ) -> Double {
        guard quota > 0 else { return 0 }
        return min(100.0, (Double(messages) / Double(quota)) * 100.0)
    }

    /// Determine color based on message quota usage
    /// Returns appropriate color based on percentage thresholds
    public static func getMessageQuotaColor(
        messages: Int,
        quota: Int = 5000
    ) -> String {
        let percent = calculateMessageQuotaPercentage(messages: messages, quota: quota)
        if percent >= 90 { return "red" }
        if percent >= 75 { return "orange" }
        if percent >= 50 { return "yellow" }
        return "secondary"
    }

    /// Get display values for the critical metric
    public static func getCriticalMetricDisplay(
        activeSession: ActiveSessionData?,
        maxTokensFromPreviousBlocks: Int?
    ) -> (current: String, limit: String, percentage: Double) {
        guard let activeSession = activeSession,
              let block = activeSession.currentBlock else {
            return ("$0.00", "$140.00", 0)
        }

        let metric = getCriticalMetric(
            activeSession: activeSession,
            maxTokensFromPreviousBlocks: maxTokensFromPreviousBlocks
        )

        if metric.isTokenCritical {
            let baseline = maxTokensFromPreviousBlocks ?? defaultTokenBaseline
            let percentage = calculateTokenPercentage(
                tokens: block.tokenCounts.totalTokens,
                maxFromPrevious: maxTokensFromPreviousBlocks
            )
            return (
                formatTokens(block.tokenCounts.totalTokens),
                formatTokens(baseline),
                percentage
            )
        } else {
            let percentage = calculateCostPercentage(
                cost: block.costUSD,
                useBlockBaseline: true
            )
            return (
                CostEstimator.formatUSD(block.costUSD),
                "$140.00",
                percentage
            )
        }
    }

    // MARK: - Helper Methods

    /// Format token count for display
    public static func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1000 {
            return String(format: "%.1fK", Double(tokens) / 1_000)
        } else {
            return "\(tokens)"
        }
    }
}