// ABOUTME: ClaudeCodeDataSource implementation for reading Claude Code JSONL usage data
// Provides DataSource trait implementation for Claude Code conversation and token usage tracking

use crate::data::database::{
    CompactionStatus, ConversationSummary, DirectoryGroup, GlobalStats,
    PeriodMetrics, QConversation, Session, TokenUsageDetails,
};
use crate::data::datasource::DataSource;
use crate::utils::cost_calculator::{CostCalculator, CostMode, TokenUsage as CostTokenUsage};
use crate::utils::error::{QStatusError, Result};
use async_trait::async_trait;
use chrono::{DateTime, Duration, Local, Utc};
use glob::glob;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

/// Claude Code usage entry from JSONL files
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
    #[serde(rename = "isApiErrorMessage")]
    pub is_api_error_message: Option<bool>,
    pub cwd: Option<String>,
    pub version: Option<String>,
}

/// Claude message structure containing usage and model info
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClaudeMessage {
    pub usage: ClaudeTokenUsage,
    pub model: Option<String>,
    pub id: Option<String>,
    pub content: Option<Vec<MessageContent>>,
}

/// Message content structure
#[derive(Debug, Clone, Serialize, Deserialize)]
struct MessageContent {
    text: Option<String>,
}

/// Token usage details from Claude
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

    /// Add another token usage to this one
    fn add(&mut self, other: &ClaudeTokenUsage) {
        self.input_tokens += other.input_tokens;
        self.output_tokens += other.output_tokens;
        self.cache_creation_input_tokens = Some(
            self.cache_creation_input_tokens.unwrap_or(0)
                + other.cache_creation_input_tokens.unwrap_or(0),
        );
        self.cache_read_input_tokens = Some(
            self.cache_read_input_tokens.unwrap_or(0)
                + other.cache_read_input_tokens.unwrap_or(0),
        );
    }
}

/// Cost breakdown tracking actual vs calculated costs
#[derive(Debug, Clone)]
pub struct CostBreakdown {
    pub total: f64,
    pub from_jsonl: f64,       // Costs from cost_usd field
    pub calculated: f64,        // Costs calculated from tokens
    pub percent_actual: f64,    // Percentage of costs that are actual
}

/// Aggregated session data
#[derive(Debug, Clone)]
pub struct ClaudeSession {
    pub id: String,
    pub project: String,
    pub directory: Option<String>,
    pub start_time: DateTime<Utc>,
    pub end_time: DateTime<Utc>,
    pub entries: Vec<ClaudeUsageEntry>,
    pub total_tokens: ClaudeTokenUsage,
    pub context_tokens: Option<ClaudeTokenUsage>,  // Current context for active sessions
    pub total_cost: f64,
    pub cost_breakdown: CostBreakdown,
    pub models: HashSet<String>,
}

/// Cache entry for tracking file modifications
#[derive(Debug, Clone)]
struct CacheEntry {
    path: PathBuf,
    modified: std::time::SystemTime,
    entries: Vec<ClaudeUsageEntry>,
}

/// Claude Code data source implementation
pub struct ClaudeCodeDataSource {
    /// Cached data
    cache: Arc<Mutex<HashMap<PathBuf, CacheEntry>>>,
    /// Last check time for changes
    last_check: Arc<Mutex<Option<std::time::SystemTime>>>,
    /// Cached sessions
    sessions: Arc<Mutex<Vec<ClaudeSession>>>,
    /// Whether cache needs refresh
    needs_refresh: Arc<Mutex<bool>>,
    /// Cost calculator instance
    cost_calculator: CostCalculator,
    /// Cost calculation mode
    cost_mode: CostMode,
}

impl ClaudeCodeDataSource {
    /// Create a new Claude Code data source
    pub fn new() -> Result<Self> {
        let source = Self {
            cache: Arc::new(Mutex::new(HashMap::new())),
            last_check: Arc::new(Mutex::new(None)),
            sessions: Arc::new(Mutex::new(Vec::new())),
            needs_refresh: Arc::new(Mutex::new(true)),
            cost_calculator: CostCalculator::new(),
            cost_mode: CostMode::Auto,
        };

        // Load initial data
        futures::executor::block_on(source.refresh_cache())?;

        Ok(source)
    }

    /// Get the currently active Claude session (within last 5 hours)
    pub async fn get_active_session(&self) -> Result<Option<ClaudeSession>> {
        if *self.needs_refresh.lock().unwrap() {
            self.refresh_cache().await?;
        }

        let sessions = self.sessions.lock().unwrap();
        let now = Utc::now();
        let five_hours_ago = now - Duration::hours(5);

        // Find the most recent session within the 5-hour window
        let active_session = sessions.iter()
            .filter(|s| s.end_time > five_hours_ago)
            .max_by_key(|s| s.end_time)
            .map(|session| {
                // For active sessions, provide both cumulative total and current context
                let mut adjusted_session = session.clone();

                // Get the most recent entry to find current context usage
                if let Some(last_entry) = session.entries.last() {
                    // Use cache_read_input_tokens as the actual context in use
                    // This is what Claude has in memory after compaction
                    let cache_read = last_entry.message.usage.cache_read_input_tokens.unwrap_or(0);
                    let cache_creation = last_entry.message.usage.cache_creation_input_tokens.unwrap_or(0);
                    let input = last_entry.message.usage.input_tokens;

                    // Set the context_tokens to show current context usage
                    adjusted_session.context_tokens = Some(ClaudeTokenUsage {
                        input_tokens: input,  // Current input tokens
                        output_tokens: 0,     // Not relevant for context display
                        cache_creation_input_tokens: Some(cache_creation),
                        cache_read_input_tokens: Some(cache_read),
                    });
                }

                // total_tokens remains unchanged - it's the cumulative total across all entries
                adjusted_session
            });

        Ok(active_session)
    }

    /// Get Claude data directories
    fn get_claude_paths(&self) -> Result<Vec<PathBuf>> {
        let mut paths = Vec::new();

        // Check environment variable first (comma-separated paths)
        if let Ok(env_paths) = std::env::var("CLAUDE_CONFIG_DIR") {
            for path_str in env_paths.split(',') {
                let path = PathBuf::from(path_str.trim());
                let projects_path = path.join("projects");
                if projects_path.exists() && projects_path.is_dir() {
                    paths.push(path);
                }
            }
        }

        // If no env paths, use defaults
        if paths.is_empty() {
            let home = dirs::home_dir()
                .ok_or_else(|| QStatusError::Config("Could not find home directory".to_string()))?;

            // Check ~/.config/claude/projects
            let config_path = home.join(".config").join("claude");
            if config_path.join("projects").exists() {
                paths.push(config_path);
            }

            // Check ~/.claude/projects
            let claude_path = home.join(".claude");
            if claude_path.join("projects").exists() {
                paths.push(claude_path);
            }
        }

        if paths.is_empty() {
            return Err(QStatusError::Config(
                "No valid Claude data directories found. Please ensure ~/.claude/projects or ~/.config/claude/projects exists".to_string()
            ));
        }

        Ok(paths)
    }

    /// Extract project name from file path
    fn extract_project_from_path(&self, jsonl_path: &Path) -> String {
        let path_str = jsonl_path.to_string_lossy();
        if let Some(projects_idx) = path_str.find("projects") {
            let after_projects = &path_str[projects_idx + 9..]; // "projects/".len()
            if let Some(slash_idx) = after_projects.find('/') {
                return after_projects[..slash_idx].to_string();
            }
        }
        "unknown".to_string()
    }

    /// Parse ISO timestamp to DateTime
    fn parse_timestamp(&self, timestamp: &str) -> Result<DateTime<Utc>> {
        DateTime::parse_from_rfc3339(timestamp)
            .map(|dt| dt.with_timezone(&Utc))
            .map_err(|e| QStatusError::Config(format!("Invalid timestamp: {}", e)))
    }

    /// Calculate cost for an entry - prioritizes actual cost_usd from JSONL
    fn calculate_cost(&self, entry: &ClaudeUsageEntry) -> f64 {
        // Always prioritize the actual cost_usd field if present
        if let Some(actual_cost) = entry.cost_usd {
            if actual_cost > 0.0 {
                return actual_cost;
            }
        }

        // Fall back to calculated cost if no actual cost
        let model = entry.message.model.as_deref().unwrap_or("claude-3-5-sonnet-20241022");

        // Convert to cost calculator's token usage format
        let tokens = CostTokenUsage {
            input_tokens: entry.message.usage.input_tokens,
            output_tokens: entry.message.usage.output_tokens,
            cache_creation_input_tokens: entry.message.usage.cache_creation_input_tokens,
            cache_read_input_tokens: entry.message.usage.cache_read_input_tokens,
        };

        self.cost_calculator.calculate_cost(
            &tokens,
            model,
            self.cost_mode,
            entry.cost_usd,
        )
    }

    /// Load JSONL files and parse entries
    async fn load_jsonl_files(&self) -> Result<Vec<ClaudeUsageEntry>> {
        let paths = self.get_claude_paths()?;
        let mut all_entries = Vec::new();
        let mut seen_ids = HashSet::new();

        for base_path in paths {
            let projects_path = base_path.join("projects");
            let pattern = projects_path.join("**/*.jsonl");

            let glob_pattern = pattern.to_string_lossy();
            for entry in glob(&glob_pattern).map_err(|e| QStatusError::Config(format!("Glob pattern error: {}", e)))? {
                let file_path = entry.map_err(|e| QStatusError::Config(format!("Glob error: {}", e)))?;

                // Read file line by line
                let content = fs::read_to_string(&file_path)
                    .map_err(|e| QStatusError::Io(e))?;

                let project = self.extract_project_from_path(&file_path);

                for line in content.lines() {
                    if line.trim().is_empty() {
                        continue;
                    }

                    // Parse JSON line
                    match serde_json::from_str::<ClaudeUsageEntry>(line) {
                        Ok(mut entry) => {
                            // Deduplicate by request ID or message ID
                            let unique_id = entry.request_id.as_ref()
                                .or(entry.message.id.as_ref())
                                .map(|s| s.to_string())
                                .unwrap_or_else(|| format!("{}-{}", entry.timestamp, entry.message.usage.total()));

                            if !seen_ids.contains(&unique_id) {
                                seen_ids.insert(unique_id);

                                // Add project directory if not in cwd
                                if entry.cwd.is_none() {
                                    entry.cwd = Some(project.clone());
                                }

                                all_entries.push(entry);
                            }
                        }
                        Err(_) => {
                            // Skip malformed lines
                            continue;
                        }
                    }
                }
            }
        }

        // Sort by timestamp
        all_entries.sort_by(|a, b| a.timestamp.cmp(&b.timestamp));

        Ok(all_entries)
    }

    /// Group entries into sessions
    fn group_into_sessions(&self, entries: Vec<ClaudeUsageEntry>) -> Vec<ClaudeSession> {
        let mut sessions_map: HashMap<String, ClaudeSession> = HashMap::new();

        for entry in entries {
            let session_id = entry.session_id.clone()
                .unwrap_or_else(|| format!("no-session-{}", entry.timestamp));

            let timestamp = self.parse_timestamp(&entry.timestamp).unwrap_or_else(|_| Utc::now());

            // Track if this cost is from JSONL or calculated
            let has_actual_cost = entry.cost_usd.is_some() && entry.cost_usd.unwrap() > 0.0;
            let cost = self.calculate_cost(&entry);

            let project = entry.cwd.clone().unwrap_or_else(|| "unknown".to_string());

            sessions_map
                .entry(session_id.clone())
                .and_modify(|session| {
                    session.end_time = timestamp;
                    session.total_tokens.add(&entry.message.usage);
                    session.total_cost += cost;

                    // Update cost breakdown
                    if has_actual_cost {
                        session.cost_breakdown.from_jsonl += cost;
                    } else {
                        session.cost_breakdown.calculated += cost;
                    }
                    session.cost_breakdown.total = session.total_cost;
                    session.cost_breakdown.percent_actual = if session.total_cost > 0.0 {
                        (session.cost_breakdown.from_jsonl / session.total_cost) * 100.0
                    } else {
                        0.0
                    };

                    if let Some(model) = &entry.message.model {
                        session.models.insert(model.clone());
                    }
                    session.entries.push(entry.clone());
                })
                .or_insert_with(|| {
                    let mut models = HashSet::new();
                    if let Some(model) = &entry.message.model {
                        models.insert(model.clone());
                    }

                    let cost_breakdown = CostBreakdown {
                        total: cost,
                        from_jsonl: if has_actual_cost { cost } else { 0.0 },
                        calculated: if has_actual_cost { 0.0 } else { cost },
                        percent_actual: if has_actual_cost { 100.0 } else { 0.0 },
                    };

                    ClaudeSession {
                        id: session_id,
                        project: project.clone(),
                        directory: entry.cwd.clone(),
                        start_time: timestamp,
                        end_time: timestamp,
                        entries: vec![entry.clone()],
                        total_tokens: entry.message.usage.clone(),
                        context_tokens: None,  // Will be set for active sessions
                        total_cost: cost,
                        cost_breakdown,
                        models,
                    }
                });
        }

        let mut sessions: Vec<ClaudeSession> = sessions_map.into_values().collect();
        sessions.sort_by(|a, b| b.end_time.cmp(&a.end_time));

        sessions
    }

    /// Refresh the cache with latest data
    async fn refresh_cache(&self) -> Result<()> {
        let entries = self.load_jsonl_files().await?;
        let sessions = self.group_into_sessions(entries);

        *self.sessions.lock().unwrap() = sessions;
        *self.needs_refresh.lock().unwrap() = false;
        *self.last_check.lock().unwrap() = Some(std::time::SystemTime::now());

        Ok(())
    }

    /// Convert Claude session to QConversation
    fn session_to_conversation(&self, session: &ClaudeSession) -> QConversation {
        // Create a simplified conversation structure
        let mut history = Vec::new();

        for entry in &session.entries {
            let mut message_pair = Vec::new();

            // Add user message placeholder
            message_pair.push(Value::Object(serde_json::Map::from_iter(vec![
                ("role".to_string(), Value::String("user".to_string())),
                ("content".to_string(), Value::String("...".to_string())),
            ])));

            // Add assistant message with content if available
            let content = entry.message.content.as_ref()
                .and_then(|c| c.first())
                .and_then(|c| c.text.clone())
                .unwrap_or_else(|| "...".to_string());

            message_pair.push(Value::Object(serde_json::Map::from_iter(vec![
                ("role".to_string(), Value::String("assistant".to_string())),
                ("content".to_string(), Value::String(content)),
            ])));

            history.push(message_pair);
        }

        QConversation {
            conversation_id: session.id.clone(),
            history,
            context_message_length: Some(session.total_tokens.total()),
            valid_history_range: None,
            transcript: None,
            tools: None,
            context_manager: None,
            latest_summary: None,
        }
    }

    /// Calculate token usage details for a session
    fn calculate_token_usage(&self, session: &ClaudeSession) -> TokenUsageDetails {
        // Check if we have context_tokens set (for active sessions)
        let (total_tokens, history_tokens, context_tokens) = if let Some(ref ctx_tokens) = session.context_tokens {
            // Use the actual context tokens for active sessions
            let context_total = ctx_tokens.total();
            let cache_read = ctx_tokens.cache_read_input_tokens.unwrap_or(0) as u64;
            let cache_creation = ctx_tokens.cache_creation_input_tokens.unwrap_or(0) as u64;

            // For display purposes, show context window usage based on actual context
            (context_total, cache_read, cache_creation)
        } else {
            // For historical sessions, use cumulative totals
            let total = session.total_tokens.total();
            let history = session.total_tokens.input_tokens as u64
                + session.total_tokens.cache_read_input_tokens.unwrap_or(0) as u64;
            let context = session.total_tokens.output_tokens as u64
                + session.total_tokens.cache_creation_input_tokens.unwrap_or(0) as u64;
            (total, history, context)
        };

        let context_window = 200_000u64; // Claude 3.5 Sonnet context window
        let percentage = (total_tokens as f64 / context_window as f64) * 100.0;

        let compaction_status = match percentage {
            p if p < 70.0 => CompactionStatus::Safe,
            p if p < 90.0 => CompactionStatus::Warning,
            p if p < 95.0 => CompactionStatus::Critical,
            _ => CompactionStatus::Imminent,
        };

        TokenUsageDetails {
            history_tokens,
            context_tokens,
            total_tokens,
            context_window,
            percentage,
            compaction_status,
            has_summary: false,
            message_count: session.entries.len(),
        }
    }
}

#[async_trait]
impl DataSource for ClaudeCodeDataSource {
    fn as_any(&self) -> &dyn std::any::Any {
        self
    }

    async fn has_changed(&mut self) -> Result<bool> {
        // Check if any JSONL files have been modified since last check
        let paths = self.get_claude_paths()?;

        for base_path in paths {
            let projects_path = base_path.join("projects");
            let pattern = projects_path.join("**/*.jsonl");

            let glob_pattern = pattern.to_string_lossy();
            for entry in glob(&glob_pattern).map_err(|e| QStatusError::Config(format!("Glob pattern error: {}", e)))? {
                let file_path = entry.map_err(|e| QStatusError::Config(format!("Glob error: {}", e)))?;
                let metadata = fs::metadata(&file_path).map_err(|e| QStatusError::Io(e))?;
                let modified = metadata.modified().map_err(|e| QStatusError::Io(e))?;

                if let Some(last_check) = *self.last_check.lock().unwrap() {
                    if modified > last_check {
                        *self.needs_refresh.lock().unwrap() = true;
                        return Ok(true);
                    }
                }
            }
        }

        Ok(false)
    }

    async fn get_current_conversation(&self, cwd: Option<&str>) -> Result<Option<QConversation>> {
        if *self.needs_refresh.lock().unwrap() {
            self.refresh_cache().await?;
        }

        let sessions = self.sessions.lock().unwrap();

        // Find the most recent session, optionally filtered by directory
        let session = if let Some(dir) = cwd {
            sessions.iter()
                .find(|s| s.directory.as_deref() == Some(dir))
        } else {
            sessions.first()
        };

        Ok(session.map(|s| self.session_to_conversation(s)))
    }

    async fn get_all_conversation_summaries(&self) -> Result<Vec<ConversationSummary>> {
        if *self.needs_refresh.lock().unwrap() {
            self.refresh_cache().await?;
        }

        let sessions = self.sessions.lock().unwrap();
        let mut summaries = Vec::new();

        for session in sessions.iter() {
            let token_usage = self.calculate_token_usage(session);

            summaries.push(ConversationSummary {
                path: session.directory.clone().unwrap_or_else(|| session.project.clone()),
                conversation_id: session.id.clone(),
                token_usage,
                last_updated: Some(session.end_time.with_timezone(&Local)),
                json_size_bytes: 0, // Not tracked for Claude Code
            });
        }

        // Sort by total tokens (largest first)
        summaries.sort_by(|a, b| b.token_usage.total_tokens.cmp(&a.token_usage.total_tokens));

        Ok(summaries)
    }

    async fn get_all_sessions(&self, _cost_per_1k: f64) -> Result<Vec<Session>> {
        if *self.needs_refresh.lock().unwrap() {
            self.refresh_cache().await?;
        }

        let sessions = self.sessions.lock().unwrap();
        let mut result = Vec::new();

        let now = Utc::now();
        let seven_days_ago = now - Duration::days(7);

        for session in sessions.iter() {
            let token_usage = self.calculate_token_usage(session);
            let is_active = session.end_time > seven_days_ago;

            result.push(Session {
                conversation_id: session.id.clone(),
                directory: session.directory.clone().unwrap_or_else(|| session.project.clone()),
                token_usage,
                last_activity: session.end_time.with_timezone(&Local),
                message_count: session.entries.len(),
                session_cost: session.total_cost,
                is_active,
                has_active_context: !session.entries.is_empty(),
            });
        }

        Ok(result)
    }

    async fn get_global_stats(&self, _cost_per_1k: f64) -> Result<GlobalStats> {
        if *self.needs_refresh.lock().unwrap() {
            self.refresh_cache().await?;
        }

        let sessions = self.sessions.lock().unwrap();

        let total_conversations = sessions.len();
        let mut total_tokens = 0u64;
        let mut total_cost = 0.0;
        let mut total_messages = 0;
        let mut conversations_warning = 0;
        let mut conversations_critical = 0;
        let mut largest_conversation: Option<ConversationSummary> = None;
        let mut largest_tokens = 0u64;

        for session in sessions.iter() {
            let tokens = session.total_tokens.total();
            total_tokens += tokens;
            total_cost += session.total_cost;
            total_messages += session.entries.len();

            let token_usage = self.calculate_token_usage(session);

            match token_usage.compaction_status {
                CompactionStatus::Warning => conversations_warning += 1,
                CompactionStatus::Critical | CompactionStatus::Imminent => conversations_critical += 1,
                _ => {}
            }

            if tokens > largest_tokens {
                largest_tokens = tokens;
                largest_conversation = Some(ConversationSummary {
                    path: session.directory.clone().unwrap_or_else(|| session.project.clone()),
                    conversation_id: session.id.clone(),
                    token_usage,
                    last_updated: Some(session.end_time.with_timezone(&Local)),
                    json_size_bytes: 0,
                });
            }
        }

        let average_tokens = if total_conversations > 0 {
            total_tokens / total_conversations as u64
        } else {
            0
        };

        Ok(GlobalStats {
            total_conversations,
            total_tokens,
            average_tokens,
            conversations_warning,
            conversations_critical,
            largest_conversation,
            total_cost_estimate: total_cost,
            total_messages,
            message_quota_used: total_messages,
            message_quota_limit: 5000,
        })
    }

    async fn get_period_metrics(&self, _cost_per_1k: f64) -> Result<PeriodMetrics> {
        if *self.needs_refresh.lock().unwrap() {
            self.refresh_cache().await?;
        }

        let sessions = self.sessions.lock().unwrap();
        let now = Utc::now();

        let today = now.date_naive();
        let week_start = now - Duration::days(7);
        let month_start = now - Duration::days(30);
        let year_start = now - Duration::days(365);

        let mut today_tokens = 0u64;
        let mut today_cost = 0.0;
        let mut week_tokens = 0u64;
        let mut week_cost = 0.0;
        let mut month_tokens = 0u64;
        let mut month_cost = 0.0;
        let mut year_tokens = 0u64;
        let mut year_cost = 0.0;

        for session in sessions.iter() {
            let tokens = session.total_tokens.total();
            let cost = session.total_cost;

            if session.end_time.date_naive() == today {
                today_tokens += tokens;
                today_cost += cost;
            }

            if session.end_time >= week_start {
                week_tokens += tokens;
                week_cost += cost;
            }

            if session.end_time >= month_start {
                month_tokens += tokens;
                month_cost += cost;
            }

            if session.end_time >= year_start {
                year_tokens += tokens;
                year_cost += cost;
            }
        }

        Ok(PeriodMetrics {
            today_tokens,
            today_cost,
            week_tokens,
            week_cost,
            month_tokens,
            month_cost,
            year_tokens,
            year_cost,
        })
    }

    async fn get_directory_groups(&self, _cost_per_1k: f64) -> Result<Vec<DirectoryGroup>> {
        if *self.needs_refresh.lock().unwrap() {
            self.refresh_cache().await?;
        }

        let sessions = self.sessions.lock().unwrap();
        let now = Utc::now();
        let seven_days_ago = now - Duration::days(7);

        let mut groups: HashMap<String, DirectoryGroup> = HashMap::new();

        for session in sessions.iter() {
            let directory = session.directory.clone().unwrap_or_else(|| session.project.clone());
            let tokens = session.total_tokens.total();
            let cost = session.total_cost;
            let is_active = session.end_time > seven_days_ago;
            let token_usage = self.calculate_token_usage(session);

            let session_data = Session {
                conversation_id: session.id.clone(),
                directory: directory.clone(),
                token_usage,
                last_activity: session.end_time.with_timezone(&Local),
                message_count: session.entries.len(),
                session_cost: cost,
                is_active,
                has_active_context: !session.entries.is_empty(),
            };

            groups
                .entry(directory.clone())
                .and_modify(|group| {
                    group.sessions.push(session_data.clone());
                    group.total_tokens += tokens;
                    group.total_cost += cost;
                    if is_active {
                        group.active_session_count += 1;
                    }
                })
                .or_insert_with(|| DirectoryGroup {
                    directory,
                    sessions: vec![session_data],
                    total_tokens: tokens,
                    total_cost: cost,
                    active_session_count: if is_active { 1 } else { 0 },
                });
        }

        let mut result: Vec<DirectoryGroup> = groups.into_values().collect();
        result.sort_by(|a, b| b.total_tokens.cmp(&a.total_tokens));

        Ok(result)
    }

    async fn get_token_usage(&self, conversation: &QConversation) -> Result<TokenUsageDetails> {
        // Find the session for this conversation
        let sessions = self.sessions.lock().unwrap();

        if let Some(session) = sessions.iter().find(|s| s.id == conversation.conversation_id) {
            Ok(self.calculate_token_usage(session))
        } else {
            // Return default if session not found
            Ok(TokenUsageDetails {
                history_tokens: 0,
                context_tokens: 0,
                total_tokens: 0,
                context_window: 200_000,
                percentage: 0.0,
                compaction_status: CompactionStatus::Safe,
                has_summary: false,
                message_count: 0,
            })
        }
    }
}

impl Default for ClaudeCodeDataSource {
    fn default() -> Self {
        Self::new().expect("Failed to create ClaudeCodeDataSource")
    }
}