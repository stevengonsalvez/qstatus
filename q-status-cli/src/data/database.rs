// ABOUTME: Read-only interface to Amazon Q's SQLite database
// Handles platform-specific paths and JSON conversation parsing

use crate::utils::error::{QStatusError, Result};
use rusqlite::{Connection, OpenFlags, OptionalExtension};
use serde::Deserialize;
use serde_json::Value;
use std::path::PathBuf;
use chrono::{DateTime, Local, Duration, TimeZone};

#[derive(Debug, Clone)]
pub enum CompactionStatus {
    Safe,      // < 70%
    Warning,   // 70-90%
    Critical,  // 90-95%
    Imminent,  // > 95%
}

#[derive(Debug, Clone)]
pub struct TokenUsageDetails {
    pub history_tokens: u64,
    pub context_tokens: u64,
    pub total_tokens: u64,
    pub context_window: u64,
    pub percentage: f64,
    pub compaction_status: CompactionStatus,
    pub has_summary: bool,
    pub message_count: usize,
}

#[derive(Debug, Clone)]
pub struct ConversationSummary {
    pub path: String,
    pub conversation_id: String,
    pub token_usage: TokenUsageDetails,
    pub last_updated: Option<DateTime<Local>>,
    pub json_size_bytes: usize,
}

#[derive(Debug, Clone)]
pub struct Session {
    pub conversation_id: String,
    pub directory: String,
    pub token_usage: TokenUsageDetails,
    pub last_activity: DateTime<Local>,
    pub message_count: usize,
    pub session_cost: f64,
    pub is_active: bool,  // Within last 7 days
    pub has_active_context: bool,  // Has context files loaded
}

#[derive(Debug, Clone)]
pub struct DirectoryGroup {
    pub directory: String,
    pub sessions: Vec<Session>,
    pub total_tokens: u64,
    pub total_cost: f64,
    pub active_session_count: usize,
}

#[derive(Debug, Clone)]
pub struct GlobalStats {
    pub total_conversations: usize,
    pub total_tokens: u64,
    pub average_tokens: u64,
    pub conversations_warning: usize,  // 70-90%
    pub conversations_critical: usize, // 90%+
    pub largest_conversation: Option<ConversationSummary>,
    pub total_cost_estimate: f64,
    pub total_messages: usize,
    pub message_quota_used: usize,
    pub message_quota_limit: usize,  // 5000 per month
}

#[derive(Debug, Deserialize)]
pub struct QConversation {
    pub conversation_id: String,
    pub history: Vec<Vec<Value>>,  // Nested array of message pairs
    pub context_message_length: Option<u64>,
    pub valid_history_range: Option<(usize, usize)>,
    pub transcript: Option<Value>,
    pub tools: Option<Value>,
    pub context_manager: Option<Value>,
    pub latest_summary: Option<String>,  // For compaction tracking
}

pub struct QDatabase {
    conn: Connection,
    pub db_path: PathBuf,
    last_data_version: Option<i32>,
}

impl QDatabase {
    pub fn new() -> Result<Self> {
        let db_path = Self::find_database()?;

        let conn = Connection::open_with_flags(
            &db_path,
            OpenFlags::SQLITE_OPEN_READ_ONLY
                | OpenFlags::SQLITE_OPEN_NO_MUTEX
                | OpenFlags::SQLITE_OPEN_SHARED_CACHE,
        )?;

        Ok(Self {
            conn,
            db_path,
            last_data_version: None,
        })
    }

    fn find_database() -> Result<PathBuf> {
        let possible_paths = vec![
            // macOS
            directories::BaseDirs::new().and_then(|dirs| {
                Some(
                    dirs.home_dir()
                        .join("Library")
                        .join("Application Support")
                        .join("amazon-q")
                        .join("data.sqlite3"),
                )
            }),
            // Linux
            directories::BaseDirs::new()
                .and_then(|dirs| Some(dirs.data_local_dir().join("amazon-q").join("data.sqlite3"))),
            // Legacy location
            directories::BaseDirs::new().and_then(|dirs| {
                Some(
                    dirs.home_dir()
                        .join(".aws")
                        .join("q")
                        .join("db")
                        .join("q.db"),
                )
            }),
        ];

        for path_opt in possible_paths.into_iter().flatten() {
            if path_opt.exists() {
                return Ok(path_opt);
            }
        }

        Err(QStatusError::DatabaseNotFound)
    }

    pub fn has_changed(&mut self) -> Result<bool> {
        let version: i32 = self
            .conn
            .query_row("PRAGMA data_version", [], |row| row.get(0))?;

        let changed = self
            .last_data_version
            .map(|last| version != last)
            .unwrap_or(true);

        self.last_data_version = Some(version);
        Ok(changed)
    }

    pub fn get_current_conversation(&self, cwd: Option<&str>) -> Result<Option<QConversation>> {
        let current_dir = std::env::current_dir().map_err(|e| QStatusError::Io(e))?;
        let current_dir_str = current_dir.to_string_lossy();
        let key = cwd.unwrap_or(&current_dir_str);

        let result: Option<String> = self
            .conn
            .query_row(
                "SELECT value FROM conversations WHERE key = ?1",
                [key],
                |row| row.get(0),
            )
            .optional()?;

        match result {
            Some(json_str) => {
                let conversation: QConversation = serde_json::from_str(&json_str)?;
                Ok(Some(conversation))
            }
            None => Ok(None),
        }
    }

    pub fn get_token_usage(&self, conversation: &QConversation) -> TokenUsageDetails {
        // Get context tokens - this might be cumulative, so we need to be careful
        let raw_context_tokens = conversation.context_message_length.unwrap_or(0);
        
        // Calculate actual tokens from conversation history using 4:1 char-to-token ratio
        let mut history_chars = 0u64;
        for message_pair in &conversation.history {
            for message in message_pair {
                let message_str = serde_json::to_string(message).unwrap_or_default();
                history_chars += message_str.len() as u64;
            }
        }
        
        // Q uses 4:1 character to token ratio
        let history_tokens = history_chars / 4;
        
        // For active context, we should only count what's currently loaded
        // If context_tokens seems unreasonably high (>100K), it's likely cumulative
        // In that case, estimate based on typical context size
        let context_tokens = if raw_context_tokens > 100_000 {
            // Likely cumulative - estimate current context as ~20K (typical for a few files)
            20_000
        } else {
            raw_context_tokens
        };
        
        let total_tokens = history_tokens + context_tokens;
        
        // Cap total tokens at context window to prevent >100% issues
        let context_window = 175_000u64;
        let total_tokens = total_tokens.min(context_window);
        
        let percentage = (total_tokens as f64 / context_window as f64) * 100.0;
        
        // Determine compaction status based on thresholds
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
            percentage: percentage.min(100.0), // Cap at 100%
            compaction_status,
            has_summary: conversation.latest_summary.is_some(),
            message_count: conversation.history.len(),
        }
    }

    pub fn get_all_conversations(&self) -> Result<Vec<(String, QConversation)>> {
        let mut stmt = self
            .conn
            .prepare("SELECT key, value FROM conversations ORDER BY key")?;

        let conversations = stmt
            .query_map([], |row| {
                let key: String = row.get(0)?;
                let json_str: String = row.get(1)?;
                Ok((key, json_str))
            })?
            .filter_map(|r| r.ok())
            .filter_map(|(key, json_str)| {
                serde_json::from_str::<QConversation>(&json_str)
                    .ok()
                    .map(|conv| (key, conv))
            })
            .collect();

        Ok(conversations)
    }
    
    pub fn get_all_conversation_summaries(&self) -> Result<Vec<ConversationSummary>> {
        let mut stmt = self
            .conn
            .prepare("SELECT key, value, LENGTH(value) as size FROM conversations ORDER BY size DESC")?;

        let mut summaries = Vec::new();
        
        let rows = stmt.query_map([], |row| {
            let key: String = row.get(0)?;
            let json_str: String = row.get(1)?;
            let size: usize = row.get(2)?;
            Ok((key, json_str, size))
        })?;

        for row in rows {
            if let Ok((path, json_str, json_size_bytes)) = row {
                if let Ok(conv) = serde_json::from_str::<QConversation>(&json_str) {
                    let token_usage = self.get_token_usage(&conv);
                    
                    summaries.push(ConversationSummary {
                        path: path.clone(),
                        conversation_id: conv.conversation_id,
                        token_usage,
                        last_updated: None, // Could parse from conversation if timestamp available
                        json_size_bytes,
                    });
                }
            }
        }

        Ok(summaries)
    }
    
    pub fn get_global_stats(&self, cost_per_1k: f64) -> Result<GlobalStats> {
        let summaries = self.get_all_conversation_summaries()?;
        
        let total_conversations = summaries.len();
        let total_tokens: u64 = summaries.iter().map(|s| s.token_usage.total_tokens).sum();
        let average_tokens = if total_conversations > 0 {
            total_tokens / total_conversations as u64
        } else {
            0
        };
        
        let conversations_warning = summaries.iter()
            .filter(|s| matches!(s.token_usage.compaction_status, CompactionStatus::Warning))
            .count();
            
        let conversations_critical = summaries.iter()
            .filter(|s| matches!(s.token_usage.compaction_status, 
                CompactionStatus::Critical | CompactionStatus::Imminent))
            .count();
            
        let largest_conversation = summaries.iter()
            .max_by_key(|s| s.token_usage.total_tokens)
            .cloned();
            
        let total_cost_estimate = (total_tokens as f64 / 1000.0) * cost_per_1k;
        
        // Calculate total messages across all conversations
        let total_messages: usize = summaries.iter().map(|s| s.token_usage.message_count).sum();
        
        // For now, assume all messages are from current month (will need actual timestamp parsing)
        let message_quota_used = total_messages;
        let message_quota_limit = 5000;
        
        Ok(GlobalStats {
            total_conversations,
            total_tokens,
            average_tokens,
            conversations_warning,
            conversations_critical,
            largest_conversation,
            total_cost_estimate,
            total_messages,
            message_quota_used,
            message_quota_limit,
        })
    }
    
    pub fn get_conversation_by_path(&self, path: &str) -> Result<Option<QConversation>> {
        let result: Option<String> = self
            .conn
            .query_row(
                "SELECT value FROM conversations WHERE key = ?1",
                [path],
                |row| row.get(0),
            )
            .optional()?;

        match result {
            Some(json_str) => {
                let conversation: QConversation = serde_json::from_str(&json_str)?;
                Ok(Some(conversation))
            }
            None => Ok(None),
        }
    }
    
    pub fn get_all_sessions(&self, cost_per_1k: f64) -> Result<Vec<Session>> {
        // Query with LENGTH to get data size as proxy for recent activity
        let mut stmt = self
            .conn
            .prepare("SELECT key, value, LENGTH(value) as size FROM conversations ORDER BY size DESC")?;

        let mut sessions = Vec::new();
        let now = Local::now();
        let seven_days_ago = now - Duration::days(7);
        
        let rows = stmt.query_map([], |row| {
            let key: String = row.get(0)?;
            let json_str: String = row.get(1)?;
            let size: i64 = row.get(2)?;
            Ok((key, json_str, size))
        })?;

        for row in rows {
            if let Ok((path, json_str, size)) = row {
                if let Ok(conv) = serde_json::from_str::<QConversation>(&json_str) {
                    let token_usage = self.get_token_usage(&conv);
                    let session_cost = (token_usage.total_tokens as f64 / 1000.0) * cost_per_1k;
                    
                    // Try to use directory modification time as proxy for last activity
                    let dir_path = std::path::Path::new(&path);
                    let last_activity = if dir_path.exists() {
                        match dir_path.metadata() {
                            Ok(metadata) => {
                                match metadata.modified() {
                                    Ok(modified) => {
                                        // Convert system time to chrono DateTime
                                        let duration = modified.duration_since(std::time::UNIX_EPOCH)
                                            .unwrap_or_default();
                                        Local.timestamp_opt(duration.as_secs() as i64, 0).single()
                                            .unwrap_or(now)
                                    }
                                    Err(_) => now - Duration::days(30)
                                }
                            }
                            Err(_) => now - Duration::days(30)
                        }
                    } else {
                        now - Duration::days(30)
                    };
                    
                    // Mark as active if directory was modified in last 7 days
                    let is_active = last_activity > seven_days_ago;
                    
                    // Check if has active context (context_tokens > 0 means files are loaded)
                    let has_active_context = token_usage.context_tokens > 0;
                    
                    sessions.push(Session {
                        conversation_id: conv.conversation_id,
                        directory: path,
                        token_usage,
                        last_activity,
                        message_count: conv.history.len(),
                        session_cost,
                        is_active,
                        has_active_context,
                    });
                }
            }
        }

        Ok(sessions)
    }
    
    pub fn get_sessions_grouped_by_directory(&self, cost_per_1k: f64) -> Result<Vec<DirectoryGroup>> {
        let sessions = self.get_all_sessions(cost_per_1k)?;
        let mut groups: std::collections::HashMap<String, DirectoryGroup> = std::collections::HashMap::new();
        
        for session in sessions {
            let entry = groups.entry(session.directory.clone()).or_insert(DirectoryGroup {
                directory: session.directory.clone(),
                sessions: Vec::new(),
                total_tokens: 0,
                total_cost: 0.0,
                active_session_count: 0,
            });
            
            entry.total_tokens += session.token_usage.total_tokens;
            entry.total_cost += session.session_cost;
            if session.is_active {
                entry.active_session_count += 1;
            }
            entry.sessions.push(session);
        }
        
        Ok(groups.into_values().collect())
    }
}
