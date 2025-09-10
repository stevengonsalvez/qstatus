// ABOUTME: Central application state following bottom's architecture
// Manages all runtime data and coordinates between components

use chrono::{DateTime, Local};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use super::config::AppConfig;
use crate::data::database::{CompactionStatus, ConversationSummary, GlobalStats, Session, DirectoryGroup};

// Type alias for usage history
pub type UsageHistory = Vec<(DateTime<Local>, u64)>;

#[derive(Debug, Clone)]
pub struct TokenUsage {
    pub used: u64,
    pub limit: u64,
    pub percentage: f64,
    pub rate_per_minute: f64,
    pub time_remaining: Option<Duration>,
    // New fields for richer information
    pub history_tokens: u64,
    pub context_tokens: u64,
    pub context_window: u64,
    pub compaction_status: CompactionStatus,
    pub has_summary: bool,
    pub message_count: usize,
}

#[derive(Debug, Clone)]
pub struct CostAnalysis {
    pub session_cost: f64,
    pub daily_cost: f64,
    pub monthly_cost: f64,
}

#[derive(Debug, Clone)]
pub enum ViewMode {
    CurrentDirectory,  // Show only current directory's conversation
    GlobalOverview,    // Show all conversations summary
    ConversationList,  // List all conversations
    SessionList,       // List all sessions grouped by directory
    SessionDetail,     // Detailed view of a specific session
}

#[derive(Debug)]
pub struct AppState {
    pub token_usage: Arc<Mutex<TokenUsage>>,
    pub cost_analysis: Arc<Mutex<CostAnalysis>>,
    pub usage_history: Arc<Mutex<UsageHistory>>,
    pub current_conversation: Arc<Mutex<Option<String>>>,
    pub is_connected: Arc<Mutex<bool>>,
    pub last_update: Arc<Mutex<DateTime<Local>>>,
    pub config: AppConfig,
    // New fields for global monitoring
    pub all_conversations: Arc<Mutex<Vec<ConversationSummary>>>,
    pub global_stats: Arc<Mutex<Option<GlobalStats>>>,
    pub view_mode: Arc<Mutex<ViewMode>>,
    pub selected_conversation_index: Arc<Mutex<usize>>,
    // Session-level tracking
    pub all_sessions: Arc<Mutex<Vec<Session>>>,
    pub directory_groups: Arc<Mutex<Vec<DirectoryGroup>>>,
    pub selected_session: Arc<Mutex<Option<Session>>>,
    pub show_active_only: Arc<Mutex<bool>>,
    pub last_refresh: Arc<Mutex<DateTime<Local>>>,
    pub scroll_offset: Arc<Mutex<u16>>,  // For scrolling in lists
}

impl AppState {
    pub fn new(config: AppConfig) -> Self {
        Self {
            token_usage: Arc::new(Mutex::new(TokenUsage {
                used: 0,
                limit: 175_000,  // Effective limit before compaction triggers
                percentage: 0.0,
                rate_per_minute: 0.0,
                time_remaining: None,
                history_tokens: 0,
                context_tokens: 0,
                context_window: 175_000,
                compaction_status: CompactionStatus::Safe,
                has_summary: false,
                message_count: 0,
            })),
            cost_analysis: Arc::new(Mutex::new(CostAnalysis {
                session_cost: 0.0,
                daily_cost: 0.0,
                monthly_cost: 0.0,
            })),
            usage_history: Arc::new(Mutex::new(Vec::with_capacity(3600))),
            current_conversation: Arc::new(Mutex::new(None)),
            is_connected: Arc::new(Mutex::new(false)),
            last_update: Arc::new(Mutex::new(Local::now())),
            config,
            all_conversations: Arc::new(Mutex::new(Vec::new())),
            global_stats: Arc::new(Mutex::new(None)),
            view_mode: Arc::new(Mutex::new(ViewMode::SessionList)), // Start with session list view
            selected_conversation_index: Arc::new(Mutex::new(0)),
            all_sessions: Arc::new(Mutex::new(Vec::new())),
            directory_groups: Arc::new(Mutex::new(Vec::new())),
            selected_session: Arc::new(Mutex::new(None)),
            show_active_only: Arc::new(Mutex::new(true)), // Default to showing only active sessions
            last_refresh: Arc::new(Mutex::new(Local::now())),
            scroll_offset: Arc::new(Mutex::new(0)),
        }
    }

    pub fn update_token_usage_details(&self, details: crate::data::database::TokenUsageDetails) {
        let mut usage = self.token_usage.lock().unwrap();
        let old_used = usage.used;
        
        // Update all fields from the detailed calculation
        usage.used = details.total_tokens;
        usage.limit = details.context_window;
        usage.percentage = details.percentage;
        usage.history_tokens = details.history_tokens;
        usage.context_tokens = details.context_tokens;
        usage.context_window = details.context_window;
        usage.compaction_status = details.compaction_status;
        usage.has_summary = details.has_summary;
        usage.message_count = details.message_count;

        // Calculate rate based on time delta
        let now = Local::now();
        let last = *self.last_update.lock().unwrap();
        let time_diff = (now - last).num_seconds() as f64 / 60.0;

        if time_diff > 0.0 {
            usage.rate_per_minute = ((details.total_tokens as i64 - old_used as i64).max(0) as f64) / time_diff;

            // Estimate time remaining
            if usage.rate_per_minute > 0.0 {
                let remaining = usage.limit - usage.used;
                let minutes = remaining as f64 / usage.rate_per_minute;
                usage.time_remaining = Some(Duration::from_secs((minutes * 60.0) as u64));
            }
        }

        // Update history
        let mut history = self.usage_history.lock().unwrap();
        history.push((now, details.total_tokens));

        // Keep only last hour of data
        if history.len() > 3600 {
            let drain_count = history.len() - 3600;
            history.drain(0..drain_count);
        }

        *self.last_update.lock().unwrap() = now;
    }
    
    // Kept for backward compatibility
    pub fn update_token_usage(&self, used: u64) {
        let details = crate::data::database::TokenUsageDetails {
            history_tokens: used,
            context_tokens: 0,
            total_tokens: used,
            context_window: 175_000,
            percentage: (used as f64 / 175_000.0) * 100.0,
            compaction_status: match (used as f64 / 175_000.0) * 100.0 {
                p if p < 70.0 => crate::data::database::CompactionStatus::Safe,
                p if p < 90.0 => crate::data::database::CompactionStatus::Warning,
                p if p < 95.0 => crate::data::database::CompactionStatus::Critical,
                _ => crate::data::database::CompactionStatus::Imminent,
            },
            has_summary: false,
            message_count: 0,
        };
        self.update_token_usage_details(details);
    }
}

#[derive(Debug, Clone)]
pub enum AppEvent {
    DatabaseUpdate(TokenUsage),
    FileChanged,
    Tick,
    Input(crossterm::event::KeyEvent),
    Resize(u16, u16),
    Quit,
}
