// ABOUTME: Session block calculator for grouping Claude usage entries into 5-hour billing blocks
// This module implements the session block algorithm for grouping usage data into time-based blocks with gap detection

use chrono::{DateTime, Datelike, Duration, TimeZone, Timelike, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

/// Default session duration in hours (Claude's billing block duration)
pub const DEFAULT_SESSION_DURATION_HOURS: i64 = 5;

/// Token usage structure matching Claude Code data format
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ClaudeTokenUsage {
    pub input_tokens: u32,
    pub output_tokens: u32,
    pub cache_creation_input_tokens: Option<u32>,
    pub cache_read_input_tokens: Option<u32>,
}

impl ClaudeTokenUsage {
    /// Calculate total tokens including cache tokens
    pub fn total(&self) -> u64 {
        self.input_tokens as u64
            + self.output_tokens as u64
            + self.cache_creation_input_tokens.unwrap_or(0) as u64
            + self.cache_read_input_tokens.unwrap_or(0) as u64
    }
}

/// Message structure from Claude usage data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClaudeMessage {
    pub usage: ClaudeTokenUsage,
    pub model: Option<String>,
    pub id: Option<String>,
}

/// Single usage entry from Claude data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClaudeUsageEntry {
    pub timestamp: String, // ISO 8601 format
    #[serde(rename = "sessionId")]
    pub session_id: Option<String>,
    pub message: ClaudeMessage,
    #[serde(rename = "costUSD")]
    pub cost_usd: Option<f64>,
    #[serde(rename = "requestId")]
    pub request_id: Option<String>,
    pub cwd: Option<String>,
    pub version: Option<String>,
    #[serde(rename = "isApiErrorMessage")]
    pub is_api_error_message: Option<bool>,
}

impl ClaudeUsageEntry {
    /// Parse timestamp to DateTime
    pub fn date(&self) -> Option<DateTime<Utc>> {
        DateTime::parse_from_rfc3339(&self.timestamp)
            .ok()
            .map(|dt| dt.with_timezone(&Utc))
    }
}

/// Aggregated token counts for different token types
#[derive(Debug, Clone, Default, PartialEq)]
pub struct TokenCounts {
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub cache_creation_input_tokens: u64,
    pub cache_read_input_tokens: u64,
}

impl TokenCounts {
    /// Calculate total tokens
    pub fn total_tokens(&self) -> u64 {
        self.input_tokens
            + self.output_tokens
            + self.cache_creation_input_tokens
            + self.cache_read_input_tokens
    }
}

/// Represents a session block (typically 5-hour billing period) with usage data
#[derive(Debug, Clone)]
pub struct SessionBlock {
    pub id: String,                      // ISO string of block start time
    pub start_time: DateTime<Utc>,
    pub end_time: DateTime<Utc>,         // startTime + 5 hours (for normal blocks) or gap end time (for gap blocks)
    pub actual_end_time: Option<DateTime<Utc>>, // Last activity in block
    pub is_active: bool,
    pub is_gap: bool,                    // True if this is a gap block
    pub entries: Vec<ClaudeUsageEntry>,
    pub token_counts: TokenCounts,
    pub cost_usd: f64,
    pub models: HashSet<String>,
}

/// Floors a timestamp to the beginning of the hour in UTC
fn floor_to_hour(timestamp: DateTime<Utc>) -> DateTime<Utc> {
    Utc.with_ymd_and_hms(
        timestamp.year(),
        timestamp.month(),
        timestamp.day(),
        timestamp.hour(),
        0,
        0,
    )
    .unwrap()
}

/// Identifies and creates session blocks from usage entries
/// Groups entries into time-based blocks (typically 5-hour periods) with gap detection
pub fn identify_session_blocks(
    entries: &[ClaudeUsageEntry],
    session_duration_hours: Option<i64>,
) -> Vec<SessionBlock> {
    if entries.is_empty() {
        return Vec::new();
    }

    let session_duration_hours = session_duration_hours.unwrap_or(DEFAULT_SESSION_DURATION_HOURS);
    let session_duration = Duration::hours(session_duration_hours);
    let mut blocks = Vec::new();

    // Sort entries by timestamp
    let mut sorted_entries: Vec<_> = entries
        .iter()
        .filter_map(|e| e.date().map(|d| (d, e.clone())))
        .collect();
    sorted_entries.sort_by_key(|(d, _)| *d);

    let mut current_block_start: Option<DateTime<Utc>> = None;
    let mut current_block_entries: Vec<ClaudeUsageEntry> = Vec::new();
    let now = Utc::now();

    for (entry_time, entry) in sorted_entries {
        if current_block_start.is_none() {
            // First entry - start a new block (floored to the hour)
            current_block_start = Some(floor_to_hour(entry_time));
            current_block_entries = vec![entry];
        } else if let Some(block_start) = current_block_start {
            let time_since_block_start = entry_time - block_start;

            if let Some(last_entry) = current_block_entries.last() {
                if let Some(last_entry_time) = last_entry.date() {
                    let time_since_last_entry = entry_time - last_entry_time;

                    if time_since_block_start > session_duration
                        || time_since_last_entry > session_duration
                    {
                        // Close current block
                        let block = create_block(
                            block_start,
                            &current_block_entries,
                            now,
                            session_duration,
                        );
                        blocks.push(block);

                        // Add gap block if there's a significant gap
                        if time_since_last_entry > session_duration {
                            if let Some(gap_block) = create_gap_block(
                                last_entry_time,
                                entry_time,
                                session_duration,
                            ) {
                                blocks.push(gap_block);
                            }
                        }

                        // Start new block (floored to the hour)
                        current_block_start = Some(floor_to_hour(entry_time));
                        current_block_entries = vec![entry];
                    } else {
                        // Add to current block
                        current_block_entries.push(entry);
                    }
                }
            }
        }
    }

    // Close the last block
    if let Some(block_start) = current_block_start {
        if !current_block_entries.is_empty() {
            let block = create_block(block_start, &current_block_entries, now, session_duration);
            blocks.push(block);
        }
    }

    blocks
}

/// Creates a session block from a start time and usage entries
fn create_block(
    start_time: DateTime<Utc>,
    entries: &[ClaudeUsageEntry],
    now: DateTime<Utc>,
    session_duration: Duration,
) -> SessionBlock {
    let end_time = start_time + session_duration;
    let actual_end_time = entries
        .last()
        .and_then(|e| e.date())
        .unwrap_or(start_time);
    let is_active = (now - actual_end_time) < session_duration && now < end_time;

    // Aggregate token counts
    let mut token_counts = TokenCounts::default();
    let mut cost_usd = 0.0;
    let mut models = HashSet::new();

    for entry in entries {
        token_counts.input_tokens += entry.message.usage.input_tokens as u64;
        token_counts.output_tokens += entry.message.usage.output_tokens as u64;
        token_counts.cache_creation_input_tokens += entry
            .message
            .usage
            .cache_creation_input_tokens
            .unwrap_or(0) as u64;
        token_counts.cache_read_input_tokens += entry
            .message
            .usage
            .cache_read_input_tokens
            .unwrap_or(0) as u64;
        cost_usd += entry.cost_usd.unwrap_or(0.0);

        if let Some(model) = &entry.message.model {
            models.insert(model.clone());
        }
    }

    SessionBlock {
        id: start_time.to_rfc3339(),
        start_time,
        end_time,
        actual_end_time: Some(actual_end_time),
        is_active,
        is_gap: false,
        entries: entries.to_vec(),
        token_counts,
        cost_usd,
        models,
    }
}

/// Creates a gap block representing periods with no activity
fn create_gap_block(
    last_activity_time: DateTime<Utc>,
    next_activity_time: DateTime<Utc>,
    session_duration: Duration,
) -> Option<SessionBlock> {
    // Only create gap blocks for gaps longer than the session duration
    let gap_duration = next_activity_time - last_activity_time;
    if gap_duration <= session_duration {
        return None;
    }

    let gap_start = last_activity_time + session_duration;
    let gap_end = next_activity_time;

    Some(SessionBlock {
        id: format!("gap-{}", gap_start.to_rfc3339()),
        start_time: gap_start,
        end_time: gap_end,
        actual_end_time: None,
        is_active: false,
        is_gap: true,
        entries: Vec::new(),
        token_counts: TokenCounts::default(),
        cost_usd: 0.0,
        models: HashSet::new(),
    })
}

/// Represents usage burn rate calculations
#[derive(Debug, Clone)]
pub struct BurnRate {
    pub tokens_per_minute: f64,
    pub tokens_per_minute_for_indicator: f64,
    pub cost_per_hour: f64,
}

/// Calculates the burn rate (tokens/minute and cost/hour) for a session block
pub fn calculate_burn_rate(block: &SessionBlock) -> Option<BurnRate> {
    if block.entries.is_empty() || block.is_gap {
        return None;
    }

    let first_entry = block.entries.first()?.date()?;
    let last_entry = block.entries.last()?.date()?;
    let duration_minutes = (last_entry - first_entry).num_minutes() as f64;

    if duration_minutes <= 0.0 {
        return None;
    }

    let total_tokens = block.token_counts.total_tokens() as f64;
    let tokens_per_minute = total_tokens / duration_minutes;

    // For burn rate indicator, use only input and output tokens
    let non_cache_tokens = (block.token_counts.input_tokens + block.token_counts.output_tokens) as f64;
    let tokens_per_minute_for_indicator = non_cache_tokens / duration_minutes;

    let cost_per_hour = (block.cost_usd / duration_minutes) * 60.0;

    Some(BurnRate {
        tokens_per_minute,
        tokens_per_minute_for_indicator,
        cost_per_hour,
    })
}

/// Represents projected usage for remaining time in a session block
#[derive(Debug, Clone)]
pub struct ProjectedUsage {
    pub total_tokens: u64,
    pub total_cost: f64,
    pub remaining_minutes: u64,
}

/// Projects total usage for an active session block based on current burn rate
pub fn project_block_usage(block: &SessionBlock) -> Option<ProjectedUsage> {
    if !block.is_active || block.is_gap {
        return None;
    }

    let burn_rate = calculate_burn_rate(block)?;
    let now = Utc::now();
    let remaining_time = block.end_time - now;
    let remaining_minutes = remaining_time.num_minutes().max(0) as f64;

    let current_tokens = block.token_counts.total_tokens() as f64;
    let projected_additional_tokens = burn_rate.tokens_per_minute * remaining_minutes;
    let total_tokens = current_tokens + projected_additional_tokens;

    let projected_additional_cost = (burn_rate.cost_per_hour / 60.0) * remaining_minutes;
    let total_cost = block.cost_usd + projected_additional_cost;

    Some(ProjectedUsage {
        total_tokens: total_tokens.round() as u64,
        total_cost: (total_cost * 100.0).round() / 100.0,
        remaining_minutes: remaining_minutes.round() as u64,
    })
}

/// Filters session blocks to include only recent ones and active blocks
pub fn filter_recent_blocks(blocks: &[SessionBlock], days: Option<i64>) -> Vec<SessionBlock> {
    let days = days.unwrap_or(3);
    let now = Utc::now();
    let cutoff_time = now - Duration::days(days);

    blocks
        .iter()
        .filter(|block| {
            // Include block if it started after cutoff or if it's still active
            block.start_time >= cutoff_time || block.is_active
        })
        .cloned()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_mock_entry(
        timestamp: DateTime<Utc>,
        input_tokens: u32,
        output_tokens: u32,
        model: &str,
        cost_usd: f64,
    ) -> ClaudeUsageEntry {
        ClaudeUsageEntry {
            timestamp: timestamp.to_rfc3339(),
            session_id: Some("test-session".to_string()),
            message: ClaudeMessage {
                usage: ClaudeTokenUsage {
                    input_tokens,
                    output_tokens,
                    cache_creation_input_tokens: Some(0),
                    cache_read_input_tokens: Some(0),
                },
                model: Some(model.to_string()),
                id: Some("msg-123".to_string()),
            },
            cost_usd: Some(cost_usd),
            request_id: Some("req-123".to_string()),
            cwd: Some("/test/dir".to_string()),
            version: Some("1.0.0".to_string()),
            is_api_error_message: Some(false),
        }
    }

    #[test]
    fn test_empty_entries() {
        let blocks = identify_session_blocks(&[], None);
        assert_eq!(blocks.len(), 0);
    }

    #[test]
    fn test_single_block_within_5_hours() {
        let base_time = Utc.with_ymd_and_hms(2024, 1, 1, 10, 0, 0).unwrap();
        let entries = vec![
            create_mock_entry(base_time, 1000, 500, "claude-sonnet", 0.01),
            create_mock_entry(
                base_time + Duration::hours(1),
                1000,
                500,
                "claude-sonnet",
                0.01,
            ),
            create_mock_entry(
                base_time + Duration::hours(2),
                1000,
                500,
                "claude-sonnet",
                0.01,
            ),
        ];

        let blocks = identify_session_blocks(&entries, None);
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].start_time, base_time);
        assert_eq!(blocks[0].entries.len(), 3);
        assert_eq!(blocks[0].token_counts.input_tokens, 3000);
        assert_eq!(blocks[0].token_counts.output_tokens, 1500);
        assert_eq!(blocks[0].cost_usd, 0.03);
    }

    #[test]
    fn test_multiple_blocks_span_more_than_5_hours() {
        let base_time = Utc.with_ymd_and_hms(2024, 1, 1, 10, 0, 0).unwrap();
        let entries = vec![
            create_mock_entry(base_time, 1000, 500, "claude-sonnet", 0.01),
            create_mock_entry(
                base_time + Duration::hours(6),
                1000,
                500,
                "claude-sonnet",
                0.01,
            ),
        ];

        let blocks = identify_session_blocks(&entries, None);
        assert_eq!(blocks.len(), 3); // first block, gap block, second block
        assert_eq!(blocks[0].entries.len(), 1);
        assert!(blocks[1].is_gap); // gap block
        assert_eq!(blocks[2].entries.len(), 1);
    }

    #[test]
    fn test_gap_block_creation() {
        let base_time = Utc.with_ymd_and_hms(2024, 1, 1, 10, 0, 0).unwrap();
        let entries = vec![
            create_mock_entry(base_time, 1000, 500, "claude-sonnet", 0.01),
            create_mock_entry(
                base_time + Duration::hours(2),
                1000,
                500,
                "claude-sonnet",
                0.01,
            ),
            create_mock_entry(
                base_time + Duration::hours(8),
                1000,
                500,
                "claude-sonnet",
                0.01,
            ),
        ];

        let blocks = identify_session_blocks(&entries, None);
        assert_eq!(blocks.len(), 3); // first block, gap block, second block
        assert_eq!(blocks[0].entries.len(), 2);
        assert!(blocks[1].is_gap);
        assert_eq!(blocks[1].entries.len(), 0);
        assert_eq!(blocks[2].entries.len(), 1);
    }

    #[test]
    fn test_floor_to_hour() {
        let entry_time = Utc.with_ymd_and_hms(2024, 1, 1, 10, 55, 30).unwrap();
        let expected_start = Utc.with_ymd_and_hms(2024, 1, 1, 10, 0, 0).unwrap();
        let entries = vec![create_mock_entry(entry_time, 1000, 500, "claude-sonnet", 0.01)];

        let blocks = identify_session_blocks(&entries, None);
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].start_time, expected_start);
    }

    #[test]
    fn test_custom_session_duration() {
        let base_time = Utc.with_ymd_and_hms(2024, 1, 1, 10, 0, 0).unwrap();
        let entries = vec![
            create_mock_entry(base_time, 1000, 500, "claude-sonnet", 0.01),
            create_mock_entry(
                base_time + Duration::hours(3),
                1000,
                500,
                "claude-sonnet",
                0.01,
            ),
        ];

        // With 2-hour duration, these should be in separate blocks
        let blocks = identify_session_blocks(&entries, Some(2));
        assert_eq!(blocks.len(), 3); // first block, gap block, second block
        assert_eq!(blocks[0].entries.len(), 1);
        assert!(blocks[1].is_gap);
        assert_eq!(blocks[2].entries.len(), 1);
    }

    #[test]
    fn test_burn_rate_calculation() {
        let base_time = Utc.with_ymd_and_hms(2024, 1, 1, 10, 0, 0).unwrap();
        let entries = vec![
            create_mock_entry(base_time, 1000, 500, "claude-sonnet", 0.01),
            create_mock_entry(
                base_time + Duration::minutes(1),
                2000,
                1000,
                "claude-sonnet",
                0.02,
            ),
        ];

        let blocks = identify_session_blocks(&entries, None);
        let burn_rate = calculate_burn_rate(&blocks[0]).unwrap();

        assert_eq!(burn_rate.tokens_per_minute, 4500.0); // 4500 tokens / 1 minute
        assert_eq!(burn_rate.tokens_per_minute_for_indicator, 4500.0); // non-cache only
        assert!((burn_rate.cost_per_hour - 1.8).abs() < 0.01); // 0.03 / 1 minute * 60 minutes
    }

    #[test]
    fn test_filter_recent_blocks() {
        let now = Utc::now();
        let recent_time = now - Duration::days(2);
        let old_time = now - Duration::days(5);

        let recent_block = SessionBlock {
            id: recent_time.to_rfc3339(),
            start_time: recent_time,
            end_time: recent_time + Duration::hours(5),
            actual_end_time: Some(recent_time),
            is_active: false,
            is_gap: false,
            entries: vec![],
            token_counts: TokenCounts::default(),
            cost_usd: 0.01,
            models: HashSet::new(),
        };

        let old_block = SessionBlock {
            id: old_time.to_rfc3339(),
            start_time: old_time,
            end_time: old_time + Duration::hours(5),
            actual_end_time: Some(old_time),
            is_active: false,
            is_gap: false,
            entries: vec![],
            token_counts: TokenCounts::default(),
            cost_usd: 0.02,
            models: HashSet::new(),
        };

        let blocks = vec![recent_block.clone(), old_block];
        let filtered = filter_recent_blocks(&blocks, None);

        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].start_time, recent_time);
    }

    #[test]
    fn test_cache_tokens_handling() {
        let base_time = Utc.with_ymd_and_hms(2024, 1, 1, 10, 0, 0).unwrap();
        let entry = ClaudeUsageEntry {
            timestamp: base_time.to_rfc3339(),
            session_id: Some("test-session".to_string()),
            message: ClaudeMessage {
                usage: ClaudeTokenUsage {
                    input_tokens: 1000,
                    output_tokens: 500,
                    cache_creation_input_tokens: Some(100),
                    cache_read_input_tokens: Some(200),
                },
                model: Some("claude-sonnet".to_string()),
                id: Some("msg-123".to_string()),
            },
            cost_usd: Some(0.01),
            request_id: Some("req-123".to_string()),
            cwd: Some("/test/dir".to_string()),
            version: Some("1.0.0".to_string()),
            is_api_error_message: Some(false),
        };

        let blocks = identify_session_blocks(&[entry], None);
        assert_eq!(blocks[0].token_counts.cache_creation_input_tokens, 100);
        assert_eq!(blocks[0].token_counts.cache_read_input_tokens, 200);
        assert_eq!(blocks[0].token_counts.total_tokens(), 1800);
    }
}