# Q-Status CLI Monitor Implementation Plan (Rust)

## Overview
High-performance terminal dashboard for real-time Amazon Q token monitoring, built with Rust and Ratatui for minimal resource usage and single-binary distribution. Targets developers who value efficient, responsive tools.

## Current State Analysis
Based on research findings:
- Q's SQLite database: `~/Library/Application Support/amazon-q/data.sqlite3` (macOS)
- Conversations stored as JSON in TEXT columns requiring parsing
- No existing monitoring infrastructure
- Target audience expects performance similar to ripgrep, bottom, bat

### Key Discoveries:
- Rust provides 8x better memory efficiency (10.8MB vs 89MB Python)
- Single binary distribution (~2-3MB) with zero dependencies
- Ratatui offers comprehensive TUI widgets with immediate-mode rendering
- Bottom/ytop architecture patterns provide proven monitoring design

## Desired End State
A lightweight, responsive terminal monitor that:
- Uses <15MB memory and <2% CPU when idle
- Updates instantly when Q database changes
- Provides smooth animations and graph rendering
- Distributes as a single 2-3MB binary
- Supports cross-platform operation (macOS, Linux, Windows)
- Matches performance expectations set by modern Rust CLI tools

## What We're NOT Doing
- Building a GUI application
- Creating a menu bar app (that's Approach A)
- Modifying Q's operation or database
- Implementing Q command interception
- Building a web interface
- Adding Python dependencies or runtime requirements
- Over-engineering with unnecessary abstractions

## Implementation Approach
Rust with Ratatui framework, following architecture patterns from bottom and ytop, with emphasis on performance, minimal resource usage, and developer-friendly distribution.

## Phase 1: Project Foundation & Core Architecture

### Overview
Establish Rust project structure following best practices from successful monitoring tools like bottom.

### Changes Required:

#### 1. Project Structure
**Files to create**:
```
q-status-cli/
├── Cargo.toml
├── README.md
├── .github/
│   └── workflows/
│       └── release.yml
├── src/
│   ├── main.rs
│   ├── lib.rs
│   ├── app/
│   │   ├── mod.rs
│   │   ├── state.rs
│   │   └── config.rs
│   ├── data/
│   │   ├── mod.rs
│   │   ├── collector.rs
│   │   └── database.rs
│   ├── ui/
│   │   ├── mod.rs
│   │   ├── dashboard.rs
│   │   └── widgets/
│   │       ├── mod.rs
│   │       ├── token_gauge.rs
│   │       ├── usage_chart.rs
│   │       └── cost_panel.rs
│   └── utils/
│       ├── mod.rs
│       └── error.rs
├── tests/
│   └── integration_test.rs
└── .gitignore
```

#### 2. Dependencies Configuration
**File**: `Cargo.toml`
```toml
[package]
name = "q-status"
version = "0.1.0"
edition = "2021"
authors = ["Your Name"]
description = "High-performance token usage monitor for Amazon Q CLI"
license = "MIT"

[dependencies]
# Core TUI framework
ratatui = "0.26"
crossterm = "0.27"

# Database
rusqlite = { version = "0.31", features = ["bundled"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

# Async runtime
tokio = { version = "1.36", features = ["full"] }
crossbeam-channel = "0.5"

# File watching
notify = "6.1"

# Configuration
toml = "0.8"
directories = "5.0"

# Error handling
anyhow = "1.0"
thiserror = "1.0"

# Utilities
chrono = "0.4"
humantime = "2.1"
byte-unit = "5.0"

# Logging (optional, for debug mode)
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }

[dev-dependencies]
tempfile = "3.10"
mockall = "0.12"
criterion = "0.5"

[profile.release]
opt-level = 3
lto = "fat"
codegen-units = 1
strip = true
panic = "abort"

[profile.release-with-debug]
inherits = "release"
strip = false

# Platform-specific optimizations
[target.'cfg(target_os = "macos")'.dependencies]
cocoa = "0.25"

[target.'cfg(target_os = "linux")'.dependencies]
libc = "0.2"

[[bin]]
name = "q-status"
path = "src/main.rs"

[[bench]]
name = "performance"
harness = false
```

#### 3. Error Handling Foundation
**File**: `src/utils/error.rs`
```rust
// ABOUTME: Centralized error handling for the application
// Provides consistent error types and conversions

use std::fmt;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum QStatusError {
    #[error("Database error: {0}")]
    Database(#[from] rusqlite::Error),
    
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    
    #[error("JSON parsing error: {0}")]
    Json(#[from] serde_json::Error),
    
    #[error("Configuration error: {0}")]
    Config(String),
    
    #[error("Q database not found at any expected location")]
    DatabaseNotFound,
    
    #[error("File watching error: {0}")]
    FileWatch(#[from] notify::Error),
    
    #[error("Terminal error: {0}")]
    Terminal(String),
}

pub type Result<T> = std::result::Result<T, QStatusError>;
```

#### 4. Application State Management
**File**: `src/app/state.rs`
```rust
// ABOUTME: Central application state following bottom's architecture
// Manages all runtime data and coordinates between components

use std::sync::{Arc, Mutex};
use chrono::{DateTime, Local};
use crossbeam_channel::{Receiver, Sender};

#[derive(Debug, Clone)]
pub struct TokenUsage {
    pub used: u64,
    pub limit: u64,
    pub percentage: f64,
    pub rate_per_minute: f64,
    pub time_remaining: Option<Duration>,
}

#[derive(Debug, Clone)]
pub struct CostAnalysis {
    pub session_cost: f64,
    pub daily_cost: f64,
    pub monthly_cost: f64,
}

#[derive(Debug)]
pub struct AppState {
    pub token_usage: Arc<Mutex<TokenUsage>>,
    pub cost_analysis: Arc<Mutex<CostAnalysis>>,
    pub usage_history: Arc<Mutex<Vec<(DateTime<Local>, u64)>>>,
    pub current_conversation: Arc<Mutex<Option<String>>>,
    pub is_connected: Arc<Mutex<bool>>,
    pub last_update: Arc<Mutex<DateTime<Local>>>,
    pub config: AppConfig,
}

impl AppState {
    pub fn new(config: AppConfig) -> Self {
        Self {
            token_usage: Arc::new(Mutex::new(TokenUsage {
                used: 0,
                limit: 44000,
                percentage: 0.0,
                rate_per_minute: 0.0,
                time_remaining: None,
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
        }
    }
    
    pub fn update_token_usage(&self, used: u64) {
        let mut usage = self.token_usage.lock().unwrap();
        let old_used = usage.used;
        usage.used = used;
        usage.percentage = (used as f64 / usage.limit as f64) * 100.0;
        
        // Calculate rate based on time delta
        let now = Local::now();
        let last = *self.last_update.lock().unwrap();
        let time_diff = (now - last).num_seconds() as f64 / 60.0;
        
        if time_diff > 0.0 {
            usage.rate_per_minute = ((used - old_used) as f64) / time_diff;
            
            // Estimate time remaining
            if usage.rate_per_minute > 0.0 {
                let remaining = usage.limit - usage.used;
                let minutes = remaining as f64 / usage.rate_per_minute;
                usage.time_remaining = Some(Duration::from_secs((minutes * 60.0) as u64));
            }
        }
        
        // Update history
        let mut history = self.usage_history.lock().unwrap();
        history.push((now, used));
        
        // Keep only last hour of data
        if history.len() > 3600 {
            history.drain(0..history.len() - 3600);
        }
        
        *self.last_update.lock().unwrap() = now;
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
```

### Success Criteria:

#### Automated Verification:
- [ ] Project builds successfully: `cargo build`
- [ ] Tests pass: `cargo test`
- [ ] Clippy passes: `cargo clippy -- -D warnings`
- [ ] Format check passes: `cargo fmt -- --check`

#### Manual Verification:
- [ ] Project structure follows Rust best practices
- [ ] Dependencies resolve without conflicts
- [ ] Error types cover all failure modes

---

## Phase 2: Database Layer & Monitoring Engine

### Overview
Implement efficient SQLite access with JSON parsing and file watching for real-time updates.

### Changes Required:

#### 1. Database Connection Layer
**File**: `src/data/database.rs`
```rust
// ABOUTME: Read-only interface to Amazon Q's SQLite database
// Handles platform-specific paths and JSON conversation parsing

use std::path::{Path, PathBuf};
use rusqlite::{Connection, OpenFlags, Result as SqliteResult};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use crate::utils::error::{QStatusError, Result};

#[derive(Debug, Deserialize)]
pub struct QConversation {
    pub conversation_id: String,
    pub history: Vec<Value>,
    pub context_message_length: Option<u64>,
    pub valid_history_range: Option<(usize, usize)>,
}

pub struct QDatabase {
    conn: Connection,
    db_path: PathBuf,
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
            dirs::data_dir()
                .map(|d| d.join("amazon-q").join("data.sqlite3")),
            Some(dirs::home_dir().unwrap()
                .join("Library")
                .join("Application Support")
                .join("amazon-q")
                .join("data.sqlite3")),
            // Linux
            dirs::data_local_dir()
                .map(|d| d.join("amazon-q").join("data.sqlite3")),
            // Legacy
            Some(dirs::home_dir().unwrap()
                .join(".aws").join("q").join("db").join("q.db")),
        ];
        
        for path_opt in possible_paths.into_iter().flatten() {
            if path_opt.exists() {
                return Ok(path_opt);
            }
        }
        
        Err(QStatusError::DatabaseNotFound)
    }
    
    pub fn has_changed(&mut self) -> Result<bool> {
        let version: i32 = self.conn
            .query_row("PRAGMA data_version", [], |row| row.get(0))?;
        
        let changed = self.last_data_version
            .map(|last| version != last)
            .unwrap_or(true);
        
        self.last_data_version = Some(version);
        Ok(changed)
    }
    
    pub fn get_current_conversation(&self, cwd: Option<&str>) -> Result<Option<QConversation>> {
        let key = cwd.unwrap_or(&std::env::current_dir()?.to_string_lossy());
        
        let result: Option<String> = self.conn
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
    
    pub fn get_token_usage(&self, conversation: &QConversation) -> (u64, u64) {
        let context_tokens = conversation.context_message_length.unwrap_or(0);
        
        // Estimate total based on message count
        let message_count = conversation.history.len() as u64;
        let estimated_total = message_count * 500 + context_tokens;
        
        (context_tokens, estimated_total)
    }
    
    pub fn get_all_conversations(&self) -> Result<Vec<(String, QConversation)>> {
        let mut stmt = self.conn.prepare(
            "SELECT key, value FROM conversations ORDER BY key"
        )?;
        
        let conversations = stmt.query_map([], |row| {
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
}
```

#### 2. Data Collection Engine
**File**: `src/data/collector.rs`
```rust
// ABOUTME: Background data collection following bottom's architecture
// Runs in separate thread to avoid blocking UI

use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::time::interval;
use crossbeam_channel::{Sender, Receiver};
use notify::{Watcher, RecursiveMode, Event, EventKind};

use crate::app::state::{AppState, AppEvent};
use crate::data::database::QDatabase;
use crate::utils::error::Result;

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
        
        watcher.watch(
            db_path.parent().unwrap(),
            RecursiveMode::NonRecursive
        )?;
        
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
        // Get current conversation
        let conversation = self.database.get_current_conversation(None)?;
        
        if let Some(conv) = conversation {
            let (context_tokens, total_tokens) = self.database.get_token_usage(&conv);
            
            // Update state
            self.state.update_token_usage(total_tokens);
            
            // Calculate costs (example rates)
            let cost_per_1k = 0.01;
            let session_cost = (total_tokens as f64 / 1000.0) * cost_per_1k;
            
            let mut cost = self.state.cost_analysis.lock().unwrap();
            cost.session_cost = session_cost;
            // TODO: Track daily/monthly from persistent storage
            
            *self.state.is_connected.lock().unwrap() = true;
            
            // Send update event
            let usage = self.state.token_usage.lock().unwrap().clone();
            self.event_tx.send(AppEvent::DatabaseUpdate(usage))?;
        }
        
        Ok(())
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
```

### Success Criteria:

#### Automated Verification:
- [ ] Database connection tests pass: `cargo test database`
- [ ] JSON parsing handles real Q data
- [ ] File watching detects changes
- [ ] Collector runs without blocking

#### Manual Verification:
- [ ] Finds Q database on different platforms
- [ ] Updates when Q is actively used
- [ ] Handles database lock gracefully

---

## Phase 3: Terminal UI Dashboard

### Overview
Build the Ratatui-based dashboard with custom widgets following bottom's modular architecture.

### Changes Required:

#### 1. Main Dashboard Implementation
**File**: `src/ui/dashboard.rs`
```rust
// ABOUTME: Main dashboard layout and rendering logic
// Implements the primary UI following Ratatui best practices

use std::sync::Arc;
use ratatui::{
    backend::Backend,
    layout::{Constraint, Direction, Layout, Rect, Alignment},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
    Frame,
};

use crate::app::state::AppState;
use crate::ui::widgets::{TokenGauge, UsageChart, CostPanel, StatusBar};

pub struct Dashboard {
    state: Arc<AppState>,
    show_help: bool,
    selected_tab: TabSelection,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum TabSelection {
    Overview,
    History,
    Settings,
}

impl Dashboard {
    pub fn new(state: Arc<AppState>) -> Self {
        Self {
            state,
            show_help: false,
            selected_tab: TabSelection::Overview,
        }
    }
    
    pub fn render<B: Backend>(&self, frame: &mut Frame<B>) {
        let size = frame.size();
        
        // Main layout: header, body, footer
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),   // Header
                Constraint::Min(0),      // Body
                Constraint::Length(3),   // Footer
            ])
            .split(size);
        
        self.render_header(frame, chunks[0]);
        
        match self.selected_tab {
            TabSelection::Overview => self.render_overview(frame, chunks[1]),
            TabSelection::History => self.render_history(frame, chunks[1]),
            TabSelection::Settings => self.render_settings(frame, chunks[1]),
        }
        
        self.render_footer(frame, chunks[2]);
        
        // Overlay help if requested
        if self.show_help {
            self.render_help_overlay(frame, size);
        }
    }
    
    fn render_header<B: Backend>(&self, frame: &mut Frame<B>, area: Rect) {
        let is_connected = *self.state.is_connected.lock().unwrap();
        let status = if is_connected { "Connected" } else { "Disconnected" };
        let status_color = if is_connected { Color::Green } else { Color::Red };
        
        let header_text = vec![
            Span::styled("Q-Status Monitor", Style::default().add_modifier(Modifier::BOLD)),
            Span::raw(" v0.1.0  ["),
            Span::styled(status, Style::default().fg(status_color)),
            Span::raw("]"),
        ];
        
        let header = Paragraph::new(Line::from(header_text))
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::Blue))
            )
            .alignment(Alignment::Center);
        
        frame.render_widget(header, area);
    }
    
    fn render_overview<B: Backend>(&self, frame: &mut Frame<B>, area: Rect) {
        // Split into panels
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(8),    // Token usage
                Constraint::Length(5),    // Cost analysis  
                Constraint::Min(10),      // Usage chart
            ])
            .split(area);
        
        // Render token gauge
        let token_gauge = TokenGauge::new(self.state.clone());
        frame.render_widget(token_gauge, chunks[0]);
        
        // Render cost panel
        let cost_panel = CostPanel::new(self.state.clone());
        frame.render_widget(cost_panel, chunks[1]);
        
        // Render usage chart
        let usage_chart = UsageChart::new(self.state.clone());
        frame.render_widget(usage_chart, chunks[2]);
    }
    
    fn render_footer<B: Backend>(&self, frame: &mut Frame<B>, area: Rect) {
        let keybinds = vec![
            ("R", "Refresh"),
            ("H", "History"),
            ("S", "Settings"),
            ("E", "Export"),
            ("?", "Help"),
            ("Q", "Quit"),
        ];
        
        let spans: Vec<Span> = keybinds
            .iter()
            .flat_map(|(key, desc)| {
                vec![
                    Span::styled(
                        format!("[{}]", key),
                        Style::default()
                            .fg(Color::Yellow)
                            .add_modifier(Modifier::BOLD)
                    ),
                    Span::raw(format!(" {} ", desc)),
                ]
            })
            .collect();
        
        let footer = Paragraph::new(Line::from(spans))
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::DarkGray))
            )
            .alignment(Alignment::Center);
        
        frame.render_widget(footer, area);
    }
    
    pub fn handle_key(&mut self, key: crossterm::event::KeyCode) -> bool {
        use crossterm::event::KeyCode;
        
        match key {
            KeyCode::Char('?') => {
                self.show_help = !self.show_help;
                true
            }
            KeyCode::Char('h') | KeyCode::Char('H') => {
                self.selected_tab = TabSelection::History;
                true
            }
            KeyCode::Char('s') | KeyCode::Char('S') => {
                self.selected_tab = TabSelection::Settings;
                true
            }
            KeyCode::Char('o') | KeyCode::Char('O') => {
                self.selected_tab = TabSelection::Overview;
                true
            }
            KeyCode::Char('q') | KeyCode::Char('Q') => false,
            _ => true,
        }
    }
}
```

#### 2. Custom Widget - Token Gauge
**File**: `src/ui/widgets/token_gauge.rs`
```rust
// ABOUTME: Token usage gauge widget with color-coded thresholds
// Shows current usage as progress bar with percentage

use std::sync::Arc;
use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Modifier, Style},
    symbols,
    text::{Line, Span},
    widgets::{Block, Borders, Gauge, Widget},
};

use crate::app::state::AppState;

pub struct TokenGauge {
    state: Arc<AppState>,
}

impl TokenGauge {
    pub fn new(state: Arc<AppState>) -> Self {
        Self { state }
    }
    
    fn get_color(&self, percentage: f64) -> Color {
        match percentage {
            p if p >= 90.0 => Color::Red,
            p if p >= 70.0 => Color::Yellow,
            _ => Color::Green,
        }
    }
}

impl Widget for TokenGauge {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let usage = self.state.token_usage.lock().unwrap();
        let percentage = usage.percentage;
        let color = self.get_color(percentage);
        
        // Create custom gauge with detailed info
        let title = format!(
            "Current Session - {} tokens/min",
            usage.rate_per_minute as u64
        );
        
        let label = format!(
            "{:,} / {:,} tokens ({}%)",
            usage.used, usage.limit,
            percentage as u16
        );
        
        let time_remaining = usage.time_remaining
            .map(|d| format!(" - {} remaining", humantime::format_duration(d)))
            .unwrap_or_default();
        
        let gauge = Gauge::default()
            .block(
                Block::default()
                    .title(title)
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(color))
            )
            .gauge_style(Style::default().fg(color))
            .percent(percentage.min(100.0) as u16)
            .label(format!("{}{}", label, time_remaining));
        
        gauge.render(area, buf);
    }
}
```

#### 3. Usage Chart Widget
**File**: `src/ui/widgets/usage_chart.rs`
```rust
// ABOUTME: Real-time usage chart showing token consumption over time
// Uses Ratatui's Chart widget with Braille markers for smooth curves

use std::sync::Arc;
use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Style},
    symbols,
    text::Span,
    widgets::{Axis, Block, Borders, Chart, Dataset, GraphType, Widget},
};

use crate::app::state::AppState;

pub struct UsageChart {
    state: Arc<AppState>,
}

impl UsageChart {
    pub fn new(state: Arc<AppState>) -> Self {
        Self { state }
    }
}

impl Widget for UsageChart {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let history = self.state.usage_history.lock().unwrap();
        
        if history.len() < 2 {
            // Not enough data yet
            let placeholder = Block::default()
                .title("Usage Graph (Last Hour)")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::DarkGray));
            placeholder.render(area, buf);
            return;
        }
        
        // Convert history to chart data
        let data: Vec<(f64, f64)> = history
            .iter()
            .enumerate()
            .map(|(i, (_, tokens))| (i as f64, *tokens as f64))
            .collect();
        
        let max_tokens = history
            .iter()
            .map(|(_, t)| *t)
            .max()
            .unwrap_or(1000) as f64;
        
        let datasets = vec![
            Dataset::default()
                .name("Token Usage")
                .marker(symbols::Marker::Braille)
                .graph_type(GraphType::Line)
                .style(Style::default().fg(Color::Cyan))
                .data(&data),
        ];
        
        let chart = Chart::new(datasets)
            .block(
                Block::default()
                    .title("Usage Graph (Last Hour)")
                    .borders(Borders::ALL)
            )
            .x_axis(
                Axis::default()
                    .title("Time")
                    .style(Style::default().fg(Color::Gray))
                    .bounds([0.0, history.len() as f64])
            )
            .y_axis(
                Axis::default()
                    .title("Tokens")
                    .style(Style::default().fg(Color::Gray))
                    .bounds([0.0, max_tokens * 1.1])
                    .labels(vec![
                        Span::raw("0"),
                        Span::raw(format!("{:.0}", max_tokens / 2.0)),
                        Span::raw(format!("{:.0}", max_tokens)),
                    ])
            );
        
        chart.render(area, buf);
    }
}
```

### Success Criteria:

#### Automated Verification:
- [ ] UI components compile: `cargo build --release`
- [ ] Widget tests pass: `cargo test ui`
- [ ] No rendering panics in edge cases
- [ ] Keyboard handling works correctly

#### Manual Verification:
- [ ] Dashboard renders correctly in terminal
- [ ] Real-time updates visible
- [ ] Color coding changes with thresholds
- [ ] Terminal resize handled gracefully
- [ ] Smooth animations and transitions

---

## Phase 4: Application Runtime & Event Loop

### Overview
Implement the main application runtime with proper event handling and terminal management.

### Changes Required:

#### 1. Main Application Entry Point
**File**: `src/main.rs`
```rust
// ABOUTME: Entry point for Q-Status Monitor application
// Sets up terminal, event loop, and coordinates all components

use std::io;
use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    Terminal,
};
use crossbeam_channel::{bounded, Receiver, Sender};

mod app;
mod data;
mod ui;
mod utils;

use app::{config::AppConfig, state::{AppState, AppEvent}};
use ui::dashboard::Dashboard;

#[tokio::main]
async fn main() -> Result<()> {
    // Parse CLI arguments
    let config = parse_args();
    
    // Initialize logging if debug mode
    if config.debug {
        tracing_subscriber::fmt()
            .with_env_filter("q_status=debug")
            .init();
    }
    
    // Setup terminal
    let mut terminal = setup_terminal()?;
    
    // Create app state
    let state = Arc::new(AppState::new(config));
    
    // Create event channels
    let (event_tx, event_rx) = bounded::<AppEvent>(100);
    
    // Spawn data collector
    let collector_handle = data::collector::spawn_collector(
        state.clone(),
        event_tx.clone()
    )?;
    
    // Spawn input handler
    spawn_input_handler(event_tx.clone());
    
    // Create dashboard
    let mut dashboard = Dashboard::new(state.clone());
    
    // Run main event loop
    let result = run_event_loop(&mut terminal, &mut dashboard, event_rx).await;
    
    // Cleanup
    restore_terminal(&mut terminal)?;
    
    // Abort background tasks
    collector_handle.abort();
    
    result
}

fn parse_args() -> AppConfig {
    use clap::{Arg, Command};
    
    let matches = Command::new("q-status")
        .version("0.1.0")
        .author("Your Name")
        .about("High-performance token usage monitor for Amazon Q CLI")
        .arg(
            Arg::new("refresh-rate")
                .short('r')
                .long("refresh-rate")
                .value_name("SECONDS")
                .help("Refresh rate in seconds")
                .default_value("2")
        )
        .arg(
            Arg::new("config")
                .short('c')
                .long("config")
                .value_name("FILE")
                .help("Path to configuration file")
        )
        .arg(
            Arg::new("debug")
                .short('d')
                .long("debug")
                .help("Enable debug logging")
                .action(clap::ArgAction::SetTrue)
        )
        .get_matches();
    
    AppConfig {
        refresh_rate: matches
            .get_one::<String>("refresh-rate")
            .and_then(|s| s.parse().ok())
            .unwrap_or(2),
        config_path: matches
            .get_one::<String>("config")
            .map(Into::into),
        debug: matches.get_flag("debug"),
        ..Default::default()
    }
}

fn setup_terminal() -> Result<Terminal<CrosstermBackend<io::Stdout>>> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    Ok(Terminal::new(backend)?)
}

fn restore_terminal(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>
) -> Result<()> {
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;
    Ok(())
}

fn spawn_input_handler(tx: Sender<AppEvent>) {
    std::thread::spawn(move || {
        loop {
            if event::poll(Duration::from_millis(100)).unwrap() {
                if let Ok(Event::Key(key)) = event::read() {
                    let _ = tx.send(AppEvent::Input(key));
                }
            }
        }
    });
}

async fn run_event_loop(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    dashboard: &mut Dashboard,
    event_rx: Receiver<AppEvent>,
) -> Result<()> {
    loop {
        // Render dashboard
        terminal.draw(|f| dashboard.render(f))?;
        
        // Handle events
        if let Ok(event) = event_rx.recv_timeout(Duration::from_millis(50)) {
            match event {
                AppEvent::Input(key) => {
                    if !dashboard.handle_key(key.code) {
                        break; // Quit requested
                    }
                }
                AppEvent::DatabaseUpdate(_) => {
                    // State already updated by collector
                }
                AppEvent::FileChanged => {
                    // Trigger refresh on next poll
                }
                AppEvent::Resize(_, _) => {
                    // Terminal will handle resize automatically
                }
                AppEvent::Quit => break,
                _ => {}
            }
        }
    }
    
    Ok(())
}
```

#### 2. Configuration Management
**File**: `src/app/config.rs`
```rust
// ABOUTME: Application configuration with defaults and file loading
// Supports TOML configuration files and environment variables

use std::path::PathBuf;
use serde::{Deserialize, Serialize};
use directories::ProjectDirs;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    pub refresh_rate: u64,
    pub token_limit: u64,
    pub warning_threshold: f64,
    pub critical_threshold: f64,
    pub cost_per_1k_tokens: f64,
    pub history_retention_hours: u64,
    pub export_format: ExportFormat,
    pub theme: Theme,
    #[serde(skip)]
    pub config_path: Option<PathBuf>,
    #[serde(skip)]
    pub debug: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ExportFormat {
    Json,
    Csv,
    Markdown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Theme {
    Dark,
    Light,
    Auto,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            refresh_rate: 2,
            token_limit: 44000,
            warning_threshold: 70.0,
            critical_threshold: 90.0,
            cost_per_1k_tokens: 0.01,
            history_retention_hours: 24,
            export_format: ExportFormat::Csv,
            theme: Theme::Dark,
            config_path: None,
            debug: false,
        }
    }
}

impl AppConfig {
    pub fn load() -> Self {
        let mut config = Self::default();
        
        // Try to load from default location
        if let Some(proj_dirs) = ProjectDirs::from("com", "q-status", "q-status") {
            let config_path = proj_dirs.config_dir().join("config.toml");
            if config_path.exists() {
                if let Ok(contents) = std::fs::read_to_string(&config_path) {
                    if let Ok(file_config) = toml::from_str::<Self>(&contents) {
                        config = file_config;
                        config.config_path = Some(config_path);
                    }
                }
            }
        }
        
        // Override with environment variables
        if let Ok(rate) = std::env::var("Q_STATUS_REFRESH_RATE") {
            if let Ok(parsed) = rate.parse() {
                config.refresh_rate = parsed;
            }
        }
        
        config
    }
    
    pub fn save(&self) -> Result<(), Box<dyn std::error::Error>> {
        if let Some(proj_dirs) = ProjectDirs::from("com", "q-status", "q-status") {
            let config_dir = proj_dirs.config_dir();
            std::fs::create_dir_all(config_dir)?;
            
            let config_path = config_dir.join("config.toml");
            let contents = toml::to_string_pretty(self)?;
            std::fs::write(config_path, contents)?;
        }
        
        Ok(())
    }
}
```

### Success Criteria:

#### Automated Verification:
- [ ] Application compiles: `cargo build --release`
- [ ] Event loop handles all event types
- [ ] Terminal setup/teardown works correctly
- [ ] Configuration loads and saves properly

#### Manual Verification:
- [ ] Application starts without errors
- [ ] Responds to keyboard input
- [ ] Updates display in real-time
- [ ] Exits cleanly with Q

---

## Phase 5: Build Optimization & Distribution

### Overview
Optimize build size, performance, and create distribution packages.

### Changes Required:

#### 1. Build Script for Optimization
**File**: `build.rs`
```rust
// ABOUTME: Build script for compile-time optimizations
// Embeds version info and optimizes for target platform

fn main() {
    // Set version from git
    if let Ok(output) = std::process::Command::new("git")
        .args(&["describe", "--tags", "--always"])
        .output()
    {
        let version = String::from_utf8_lossy(&output.stdout);
        println!("cargo:rustc-env=GIT_VERSION={}", version.trim());
    }
    
    // Platform-specific optimizations
    #[cfg(target_os = "macos")]
    {
        println!("cargo:rustc-link-arg=-framework");
        println!("cargo:rustc-link-arg=CoreFoundation");
    }
    
    #[cfg(target_os = "windows")]
    {
        // Embed Windows manifest for DPI awareness
        embed_resource::compile("resources/windows/q-status.rc");
    }
}
```

#### 2. GitHub Actions Release Pipeline
**File**: `.github/workflows/release.yml`
```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

env:
  CARGO_TERM_COLOR: always

jobs:
  build:
    strategy:
      matrix:
        include:
          - os: ubuntu-latest
            target: x86_64-unknown-linux-musl
            binary: q-status
          - os: macos-latest
            target: x86_64-apple-darwin
            binary: q-status
          - os: macos-latest
            target: aarch64-apple-darwin
            binary: q-status
          - os: windows-latest
            target: x86_64-pc-windows-msvc
            binary: q-status.exe
    
    runs-on: ${{ matrix.os }}
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Install Rust
      uses: dtolnay/rust-toolchain@stable
      with:
        targets: ${{ matrix.target }}
    
    - name: Install dependencies (Linux)
      if: matrix.os == 'ubuntu-latest'
      run: |
        sudo apt-get update
        sudo apt-get install -y musl-tools
    
    - name: Build
      run: |
        cargo build --release --target ${{ matrix.target }}
        
    - name: Strip binary (Unix)
      if: matrix.os != 'windows-latest'
      run: |
        strip target/${{ matrix.target }}/release/${{ matrix.binary }}
        
    - name: Package
      run: |
        cd target/${{ matrix.target }}/release
        tar czf ../../../q-status-${{ matrix.target }}.tar.gz ${{ matrix.binary }}
        cd ../../..
        
    - name: Upload artifact
      uses: actions/upload-artifact@v3
      with:
        name: q-status-${{ matrix.target }}
        path: q-status-${{ matrix.target }}.tar.gz

  release:
    needs: build
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Download artifacts
      uses: actions/download-artifact@v3
      
    - name: Create Release
      uses: softprops/action-gh-release@v1
      with:
        files: q-status-*/q-status-*.tar.gz
        draft: false
        prerelease: false
        generate_release_notes: true
```

#### 3. Installation Script
**File**: `install.sh`
```bash
#!/usr/bin/env bash
# ABOUTME: Cross-platform installation script for Q-Status Monitor
# Downloads appropriate binary and installs to PATH

set -e

REPO="yourusername/q-status-cli"
INSTALL_DIR="${Q_STATUS_INSTALL_DIR:-$HOME/.local/bin}"

# Detect OS and architecture
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux*)
        case "$ARCH" in
            x86_64) TARGET="x86_64-unknown-linux-musl" ;;
            aarch64) TARGET="aarch64-unknown-linux-musl" ;;
            *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
        esac
        ;;
    Darwin*)
        case "$ARCH" in
            x86_64) TARGET="x86_64-apple-darwin" ;;
            arm64) TARGET="aarch64-apple-darwin" ;;
            *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
        esac
        ;;
    MINGW*|MSYS*|CYGWIN*)
        TARGET="x86_64-pc-windows-msvc"
        ;;
    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

# Get latest release
echo "Fetching latest release..."
LATEST=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST" ]; then
    echo "Failed to fetch latest release"
    exit 1
fi

# Download binary
URL="https://github.com/$REPO/releases/download/$LATEST/q-status-$TARGET.tar.gz"
echo "Downloading Q-Status $LATEST for $TARGET..."

TMP_DIR=$(mktemp -d)
curl -L "$URL" | tar xz -C "$TMP_DIR"

# Install
mkdir -p "$INSTALL_DIR"
mv "$TMP_DIR/q-status" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/q-status"
rm -rf "$TMP_DIR"

echo "Q-Status installed to $INSTALL_DIR/q-status"
echo "Make sure $INSTALL_DIR is in your PATH"
```

### Success Criteria:

#### Automated Verification:
- [ ] Release builds successfully: `cargo build --release`
- [ ] Binary size < 3MB after stripping
- [ ] Cross-compilation works for all targets
- [ ] CI/CD pipeline passes

#### Manual Verification:
- [ ] Installation script works on macOS/Linux
- [ ] Binary runs on target platforms
- [ ] No dynamic dependencies required
- [ ] Performance meets targets (<15MB RAM, <2% CPU)

---

## Testing Strategy

### Unit Tests:
- Database connection and queries
- Token usage calculations
- Rate calculations
- Configuration loading
- Widget rendering

### Integration Tests:
- End-to-end monitoring flow
- UI updates with mock data
- File watching detection
- Event handling

### Performance Benchmarks:
```rust
// benches/performance.rs
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn benchmark_database_query(c: &mut Criterion) {
    c.bench_function("database query", |b| {
        b.iter(|| {
            // Benchmark database operations
        });
    });
}

fn benchmark_ui_render(c: &mut Criterion) {
    c.bench_function("ui render", |b| {
        b.iter(|| {
            // Benchmark UI rendering
        });
    });
}

criterion_group!(benches, benchmark_database_query, benchmark_ui_render);
criterion_main!(benches);
```

### Manual Testing Steps:
1. Install Q-Status: `cargo install --path .`
2. Run monitor: `q-status`
3. Use Amazon Q in another terminal
4. Verify real-time updates
5. Test all keyboard shortcuts
6. Resize terminal window
7. Test on different platforms

## Performance Targets
- **Memory usage**: < 15MB resident
- **CPU usage**: < 2% when idle, < 5% during updates
- **Startup time**: < 100ms
- **Binary size**: < 3MB stripped
- **Update latency**: < 50ms from database change to UI update

## Distribution Strategy

### Installation Methods:
1. **Direct download**: Pre-built binaries from GitHub releases
2. **Cargo**: `cargo install q-status`
3. **Homebrew**: `brew install q-status`
4. **AUR (Arch)**: `yay -S q-status`
5. **Install script**: `curl -sSf https://raw.githubusercontent.com/... | sh`

### Binary Optimization:
- Use `strip` to remove symbols
- Enable LTO (Link Time Optimization)
- Use `opt-level = 3` for maximum performance
- Static linking with musl for Linux
- Code signing for macOS (optional)

## Migration Path
- Version 0.1.0 - Initial release, no migration needed
- Future versions will use versioned configuration
- Database schema changes handled gracefully
- Backward compatibility for configuration files

## References
- Original requirements: `q-status-requirements.md`
- Rust research findings: Performance advantages and architecture patterns
- Ratatui documentation: https://ratatui.rs/
- Bottom source code: https://github.com/ClementTsang/bottom
- Q database location: `~/Library/Application Support/amazon-q/data.sqlite3`