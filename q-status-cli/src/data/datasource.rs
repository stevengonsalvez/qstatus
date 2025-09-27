// ABOUTME: DataSource trait abstraction for data access
// Provides a generic interface for reading Q usage data, enabling alternative implementations

use crate::utils::error::Result;
use crate::data::database::{
    ConversationSummary, DirectoryGroup, GlobalStats,
    PeriodMetrics, QConversation, Session, TokenUsageDetails
};
use async_trait::async_trait;
use std::any::Any;

/// Trait for abstracting data source access in q-status-cli
///
/// This trait defines the interface for reading Q usage data, allowing for
/// different implementations (e.g., SQLite database, mock data, remote API).
/// All implementations must be thread-safe (Send + Sync).
#[async_trait]
pub trait DataSource: Send + Sync {
    /// Get the concrete type as Any for downcasting
    fn as_any(&self) -> &dyn Any;
    /// Check if the underlying data has changed since last read
    ///
    /// Returns true if data has been modified, false otherwise.
    /// Implementations should track data version or modification time internally.
    async fn has_changed(&mut self) -> Result<bool>;

    /// Get the current conversation for the given working directory
    ///
    /// If `cwd` is None, returns the most recently active conversation.
    /// Returns None if no conversation exists.
    async fn get_current_conversation(&self, cwd: Option<&str>) -> Result<Option<QConversation>>;

    /// Get summaries of all conversations
    ///
    /// Returns a vector of conversation summaries ordered by size (largest first).
    /// Includes token usage, compaction status, and metadata for each conversation.
    async fn get_all_conversation_summaries(&self) -> Result<Vec<ConversationSummary>>;

    /// Get all sessions with cost calculation
    ///
    /// Returns all Q sessions with token usage and cost estimates.
    /// `cost_per_1k` specifies the cost per 1000 tokens for calculations.
    async fn get_all_sessions(&self, cost_per_1k: f64) -> Result<Vec<Session>>;

    /// Get global usage statistics
    ///
    /// Returns aggregated statistics across all conversations.
    /// `cost_per_1k` specifies the cost per 1000 tokens for calculations.
    async fn get_global_stats(&self, cost_per_1k: f64) -> Result<GlobalStats>;

    /// Get usage metrics for different time periods
    ///
    /// Returns token usage and cost metrics for today, week, month, and year.
    /// `cost_per_1k` specifies the cost per 1000 tokens for calculations.
    async fn get_period_metrics(&self, cost_per_1k: f64) -> Result<PeriodMetrics>;

    /// Get sessions grouped by directory
    ///
    /// Returns sessions organized by their working directory with aggregated metrics.
    /// `cost_per_1k` specifies the cost per 1000 tokens for calculations.
    async fn get_directory_groups(&self, cost_per_1k: f64) -> Result<Vec<DirectoryGroup>>;

    /// Calculate token usage details for a conversation
    ///
    /// Analyzes a conversation to determine token usage, compaction status,
    /// and other metrics. This is typically used for the current active conversation.
    async fn get_token_usage(&self, conversation: &QConversation) -> Result<TokenUsageDetails>;
}

/// Mock implementation of DataSource for testing
#[cfg(test)]
use crate::data::database::CompactionStatus;

#[cfg(test)]
pub struct MockDataSource {
    pub has_changed_response: bool,
    pub conversations: Vec<QConversation>,
    pub summaries: Vec<ConversationSummary>,
    pub sessions: Vec<Session>,
    pub global_stats: Option<GlobalStats>,
    pub period_metrics: Option<PeriodMetrics>,
    pub directory_groups: Vec<DirectoryGroup>,
}

#[cfg(test)]
impl MockDataSource {
    pub fn new() -> Self {
        Self {
            has_changed_response: false,
            conversations: Vec::new(),
            summaries: Vec::new(),
            sessions: Vec::new(),
            global_stats: None,
            period_metrics: None,
            directory_groups: Vec::new(),
        }
    }
}

#[cfg(test)]
#[async_trait]
impl DataSource for MockDataSource {
    async fn has_changed(&mut self) -> Result<bool> {
        Ok(self.has_changed_response)
    }

    async fn get_current_conversation(&self, _cwd: Option<&str>) -> Result<Option<QConversation>> {
        Ok(self.conversations.first().cloned())
    }

    async fn get_all_conversation_summaries(&self) -> Result<Vec<ConversationSummary>> {
        Ok(self.summaries.clone())
    }

    async fn get_all_sessions(&self, _cost_per_1k: f64) -> Result<Vec<Session>> {
        Ok(self.sessions.clone())
    }

    async fn get_global_stats(&self, _cost_per_1k: f64) -> Result<GlobalStats> {
        self.global_stats.clone()
            .ok_or_else(|| crate::utils::error::QStatusError::Config("No global stats available".to_string()))
    }

    async fn get_period_metrics(&self, _cost_per_1k: f64) -> Result<PeriodMetrics> {
        self.period_metrics.clone()
            .ok_or_else(|| crate::utils::error::QStatusError::Config("No period metrics available".to_string()))
    }

    async fn get_directory_groups(&self, _cost_per_1k: f64) -> Result<Vec<DirectoryGroup>> {
        Ok(self.directory_groups.clone())
    }

    async fn get_token_usage(&self, conversation: &QConversation) -> Result<TokenUsageDetails> {
        // Simple mock implementation - would be more sophisticated in real tests
        let history_tokens = conversation.history.len() as u64 * 100;
        let context_tokens = conversation.context_message_length.unwrap_or(0);
        let total_tokens = history_tokens + context_tokens;
        let context_window = 175_000u64;
        let percentage = (total_tokens as f64 / context_window as f64) * 100.0;

        let compaction_status = match percentage {
            p if p < 70.0 => CompactionStatus::Safe,
            p if p < 90.0 => CompactionStatus::Warning,
            p if p < 95.0 => CompactionStatus::Critical,
            _ => CompactionStatus::Imminent,
        };

        Ok(TokenUsageDetails {
            history_tokens,
            context_tokens,
            total_tokens,
            context_window,
            percentage,
            compaction_status,
            has_summary: conversation.latest_summary.is_some(),
            message_count: conversation.history.len(),
        })
    }
}