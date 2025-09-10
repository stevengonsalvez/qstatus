// ABOUTME: Background data collection following bottom's architecture
// Runs in separate thread to avoid blocking UI

use crate::app::state::{AppEvent, AppState, TokenSnapshot};
use crate::data::database::QDatabase;
use crate::utils::error::Result;
use crossbeam_channel::Sender;
use notify::{Event, EventKind, RecursiveMode, Watcher};
use std::sync::Arc;
use std::time::Duration;
use tokio::time::interval;
use chrono::Local;

pub struct DataCollector {
    state: Arc<AppState>,
    database: QDatabase,
    event_tx: Sender<AppEvent>,
    file_watcher: Option<notify::RecommendedWatcher>,
}

impl DataCollector {
    pub fn new(state: Arc<AppState>, event_tx: Sender<AppEvent>) -> Result<Self> {
        let database = QDatabase::new()?;

        Ok(Self {
            state,
            database,
            event_tx,
            file_watcher: None,
        })
    }

    pub fn start_file_watching(&mut self) -> Result<()> {
        let tx = self.event_tx.clone();
        let db_path = self.database.db_path.clone();

        let mut watcher = notify::recommended_watcher(move |res: notify::Result<Event>| {
            if let Ok(event) = res {
                if matches!(event.kind, EventKind::Modify(_)) {
                    let _ = tx.send(AppEvent::FileChanged);
                }
            }
        })?;

        watcher.watch(db_path.parent().unwrap(), RecursiveMode::NonRecursive)?;

        self.file_watcher = Some(watcher);
        Ok(())
    }

    pub async fn run(mut self) {
        // Start file watching
        if let Err(e) = self.start_file_watching() {
            eprintln!("Failed to start file watching: {}", e);
        }

        // Polling interval
        let mut ticker = interval(Duration::from_secs(2));

        loop {
            ticker.tick().await;

            // Check for database changes
            match self.database.has_changed() {
                Ok(true) => {
                    if let Err(e) = self.collect_data() {
                        eprintln!("Data collection error: {}", e);
                    }
                }
                Ok(false) => {
                    // No changes, skip collection
                }
                Err(e) => {
                    eprintln!("Database check error: {}", e);
                    *self.state.is_connected.lock().unwrap() = false;
                }
            }
        }
    }

    fn collect_data(&mut self) -> Result<()> {
        // Mark as connected if database is accessible
        *self.state.is_connected.lock().unwrap() = true;
        
        // Collect ALL conversations for global view
        let all_summaries = self.database.get_all_conversation_summaries()?;
        *self.state.all_conversations.lock().unwrap() = all_summaries.clone();
        
        // Collect session-level data
        let all_sessions = self.database.get_all_sessions(self.state.config.cost_per_1k_tokens)?;
        *self.state.all_sessions.lock().unwrap() = all_sessions.clone();
        
        // Collect grouped sessions
        let directory_groups = self.database.get_sessions_grouped_by_directory(self.state.config.cost_per_1k_tokens)?;
        *self.state.directory_groups.lock().unwrap() = directory_groups.clone();
        
        // Calculate global stats
        let global_stats = self.database.get_global_stats(self.state.config.cost_per_1k_tokens)?;
        *self.state.global_stats.lock().unwrap() = Some(global_stats.clone());
        
        // Get period-based metrics
        if let Ok(period_metrics) = self.database.get_period_metrics(self.state.config.cost_per_1k_tokens) {
            *self.state.period_metrics.lock().unwrap() = Some(period_metrics);
        }
        
        // Update last refresh time
        *self.state.last_refresh.lock().unwrap() = chrono::Local::now();
        
        // Also get current directory conversation
        let conversation = self.database.get_current_conversation(None)?;

        if let Some(conv) = conversation {
            // Get detailed token usage
            let usage_details = self.database.get_token_usage(&conv);
            
            // Update state with detailed information
            self.state.update_token_usage_details(usage_details.clone());
            
            // Update conversation ID
            *self.state.current_conversation.lock().unwrap() = Some(conv.conversation_id.clone());

            // Calculate costs
            let cost_per_1k = self.state.config.cost_per_1k_tokens;
            let session_cost = (usage_details.total_tokens as f64 / 1000.0) * cost_per_1k;

            let mut cost = self.state.cost_analysis.lock().unwrap();
            cost.session_cost = session_cost;
            
            // Update monthly cost from global stats
            if let Some(ref stats) = *self.state.global_stats.lock().unwrap() {
                cost.monthly_cost = stats.total_cost_estimate;
            }

            // Send update event
            let usage = self.state.token_usage.lock().unwrap().clone();
            self.event_tx.send(AppEvent::DatabaseUpdate(usage))?;
        } else {
            // No conversation in current directory, but still connected to database
            // Clear the usage but keep connected status
            let empty_details = crate::data::database::TokenUsageDetails {
                history_tokens: 0,
                context_tokens: 0,
                total_tokens: 0,
                context_window: 175_000,  // Effective limit before compaction
                percentage: 0.0,
                compaction_status: crate::data::database::CompactionStatus::Safe,
                has_summary: false,
                message_count: 0,
            };
            self.state.update_token_usage_details(empty_details);
            *self.state.current_conversation.lock().unwrap() = None;
        }

        // Calculate burn rate
        self.calculate_burn_rate();
        
        Ok(())
    }
    
    fn calculate_burn_rate(&self) {
        let all_sessions = self.state.all_sessions.lock().unwrap();
        let total_tokens: u64 = all_sessions.iter().map(|s| s.token_usage.total_tokens).sum();
        
        let mut burn_rate = self.state.burn_rate.lock().unwrap();
        let now = Local::now();
        
        // Add current snapshot
        burn_rate.snapshots.push_back(TokenSnapshot {
            timestamp: now,
            total_tokens,
        });
        
        // Keep only last 10 minutes of snapshots
        while burn_rate.snapshots.len() > 10 {
            burn_rate.snapshots.pop_front();
        }
        
        // Calculate burn rate if we have at least 2 snapshots
        if burn_rate.snapshots.len() >= 2 {
            let oldest = burn_rate.snapshots.front().unwrap();
            let newest = burn_rate.snapshots.back().unwrap();
            
            let time_diff = newest.timestamp.signed_duration_since(oldest.timestamp);
            let minutes = time_diff.num_seconds() as f64 / 60.0;
            
            if minutes > 0.0 {
                let token_diff = newest.total_tokens as i64 - oldest.total_tokens as i64;
                burn_rate.tokens_per_minute = (token_diff as f64 / minutes).max(0.0);
                burn_rate.cost_per_minute = (burn_rate.tokens_per_minute / 1000.0) * self.state.config.cost_per_1k_tokens;
            }
        }
    }
}

pub fn spawn_collector(
    state: Arc<AppState>,
    event_tx: Sender<AppEvent>,
) -> Result<tokio::task::JoinHandle<()>> {
    let collector = DataCollector::new(state, event_tx)?;

    Ok(tokio::spawn(async move {
        collector.run().await;
    }))
}
