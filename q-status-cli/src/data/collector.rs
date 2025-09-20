// ABOUTME: Background data collection following bottom's architecture
// Runs in separate thread to avoid blocking UI

use crate::app::state::{AppEvent, AppState, TokenSnapshot};
use crate::data::database::QDatabase;
use crate::data::datasource::DataSource;
use crate::utils::error::Result;
use crossbeam_channel::Sender;
use std::sync::Arc;
use std::time::Duration;
use tokio::time::interval;
use chrono::Local;

pub struct DataCollector {
    state: Arc<AppState>,
    database: Box<dyn DataSource>,
    event_tx: Sender<AppEvent>,
    _file_watcher: Option<notify::RecommendedWatcher>,  // Prefixed with _ to indicate intentionally unused
}

impl DataCollector {
    pub fn new(state: Arc<AppState>, database: Box<dyn DataSource>, event_tx: Sender<AppEvent>) -> Result<Self> {
        Ok(Self {
            state,
            database,
            event_tx,
            _file_watcher: None,
        })
    }

    pub fn start_file_watching(&mut self) -> Result<()> {
        // File watching is specific to QDatabase implementation
        // For now, we'll skip it when using the trait abstraction
        // TODO: Add a method to DataSource trait to get watch path if needed
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
            match self.database.has_changed().await {
                Ok(true) => {
                    if let Err(e) = self.collect_data().await {
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

    async fn collect_data(&mut self) -> Result<()> {
        // Mark as connected if database is accessible
        *self.state.is_connected.lock().unwrap() = true;
        
        // Collect ALL conversations for global view
        let all_summaries = self.database.get_all_conversation_summaries().await?;
        *self.state.all_conversations.lock().unwrap() = all_summaries.clone();

        // Collect session-level data
        let all_sessions = self.database.get_all_sessions(self.state.config.cost_per_1k_tokens).await?;
        *self.state.all_sessions.lock().unwrap() = all_sessions.clone();

        // Collect grouped sessions
        let directory_groups = self.database.get_directory_groups(self.state.config.cost_per_1k_tokens).await?;
        *self.state.directory_groups.lock().unwrap() = directory_groups.clone();

        // Calculate global stats
        let global_stats = self.database.get_global_stats(self.state.config.cost_per_1k_tokens).await?;
        *self.state.global_stats.lock().unwrap() = Some(global_stats.clone());

        // Get period-based metrics
        if let Ok(period_metrics) = self.database.get_period_metrics(self.state.config.cost_per_1k_tokens).await {
            *self.state.period_metrics.lock().unwrap() = Some(period_metrics);
        }
        
        // Update last refresh time
        *self.state.last_refresh.lock().unwrap() = chrono::Local::now();

        // Update active Claude session if using Claude data source
        let data_source = self.state.get_active_data_source();
        if matches!(data_source, crate::data::DataSourceType::ClaudeCode) {
            // Try to downcast to ClaudeCodeDataSource to get active session
            if let Some(claude_source) = self.database.as_any().downcast_ref::<crate::data::claude_datasource::ClaudeCodeDataSource>() {
                if let Ok(active_session) = claude_source.get_active_session().await {
                    self.state.set_active_claude_session(active_session);
                }
            }
        }

        // Also get latest conversation (most recently modified)
        let conversation = self.database.get_current_conversation(None).await?;

        if let Some(conv) = conversation {
            // Get detailed token usage
            let usage_details = self.database.get_token_usage(&conv).await.unwrap_or_else(|_| {
                // Fallback to empty details if there's an error
                crate::data::database::TokenUsageDetails {
                    history_tokens: 0,
                    context_tokens: 0,
                    total_tokens: 0,
                    context_window: 175_000,
                    percentage: 0.0,
                    compaction_status: crate::data::database::CompactionStatus::Safe,
                    has_summary: false,
                    message_count: 0,
                }
            });
            
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
            // No conversation found, but still connected to database
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
        const EMA_ALPHA: f64 = 0.3;  // Same as menubar app specification
        
        let all_sessions = self.state.all_sessions.lock().unwrap();
        let total_tokens: u64 = all_sessions.iter().map(|s| s.token_usage.total_tokens).sum();
        
        let mut burn_rate = self.state.burn_rate.lock().unwrap();
        let now = Local::now();
        
        // Calculate instant rate using time since last update
        let time_since_last = now.signed_duration_since(burn_rate.last_update);
        let minutes_elapsed = time_since_last.num_seconds() as f64 / 60.0;
        
        let instant_rate = if minutes_elapsed > 0.0 && burn_rate.last_total_tokens > 0 {
            let token_diff = total_tokens as i64 - burn_rate.last_total_tokens as i64;
            (token_diff as f64 / minutes_elapsed).max(0.0)
        } else {
            0.0
        };
        
        // Apply EMA smoothing: new_rate = alpha * instant_rate + (1 - alpha) * previous_rate
        if burn_rate.last_total_tokens == 0 {
            // First reading, use instant rate
            burn_rate.ema_tokens_per_minute = instant_rate;
        } else {
            // Apply EMA formula
            burn_rate.ema_tokens_per_minute = EMA_ALPHA * instant_rate + (1.0 - EMA_ALPHA) * burn_rate.ema_tokens_per_minute;
        }
        
        // Update the displayed rate to use the smoothed EMA value
        burn_rate.tokens_per_minute = burn_rate.ema_tokens_per_minute;
        burn_rate.cost_per_minute = (burn_rate.ema_tokens_per_minute / 1000.0) * self.state.config.cost_per_1k_tokens;
        
        // Update tracking values for next calculation
        burn_rate.last_update = now;
        burn_rate.last_total_tokens = total_tokens;
        
        // Still maintain snapshots for history/sparkline visualization
        burn_rate.snapshots.push_back(TokenSnapshot {
            timestamp: now,
            total_tokens,
        });
        
        // Keep only last 10 minutes of snapshots for sparkline
        while burn_rate.snapshots.len() > 10 {
            burn_rate.snapshots.pop_front();
        }
    }
}

pub fn spawn_collector(
    state: Arc<AppState>,
    event_tx: Sender<AppEvent>,
) -> Result<tokio::task::JoinHandle<()>> {
    // Create a QDatabase and box it as a DataSource
    let database = QDatabase::new()?;
    let database_box: Box<dyn DataSource> = Box::new(database);

    let collector = DataCollector::new(state, database_box, event_tx)?;

    Ok(tokio::spawn(async move {
        collector.run().await;
    }))
}

pub fn spawn_collector_with_datasource(
    state: Arc<AppState>,
    event_tx: Sender<AppEvent>,
    datasource: Box<dyn DataSource>,
) -> Result<tokio::task::JoinHandle<()>> {
    let collector = DataCollector::new(state, datasource, event_tx)?;

    Ok(tokio::spawn(async move {
        collector.run().await;
    }))
}
