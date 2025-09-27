// ABOUTME: Entry point for Q-Status Monitor application
// Sets up terminal, event loop, and coordinates all components

use anyhow::Result;
use clap::{Arg, ArgAction, Command};
use crossbeam_channel::{bounded, Receiver, Sender};
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use q_status::{
    app::{
        config::AppConfig,
        state::{AppEvent, AppState},
    },
    ui::dashboard::Dashboard,
};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::io;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::task::JoinHandle;

#[tokio::main]
async fn main() -> Result<()> {
    // Parse CLI arguments
    let mut config = parse_args();

    // Create app state
    let state = Arc::new(AppState::new(config.clone()));

    // Initialize logging if debug mode
    if config.debug {
        tracing_subscriber::fmt()
            .with_env_filter("q_status=debug")
            .init();
    }

    // Check if we're in a TTY
    if !atty::is(atty::Stream::Stdout) {
        // Non-interactive mode - just print status and exit
        return run_status_check(state.clone()).await;
    }

    // Setup terminal
    let mut terminal = setup_terminal()?;

    // Create event channels
    let (event_tx, event_rx) = bounded::<AppEvent>(100);

    // Determine which data source to use
    let source_type = q_status::data::DataSourceType::from_str(&config.data_source)
        .unwrap_or(q_status::data::DataSourceType::AmazonQ);

    // Update config with active data source
    config.active_data_source = Some(source_type);
    let state = Arc::new(AppState::new(config.clone()));

    // Try to spawn data collector with appropriate data source
    let collector_handle = match q_status::data::DataSourceFactory::create_with_fallback(
        source_type,
        config.cost_per_1k_tokens,
    ) {
        Ok((data_source, actual_type)) => {
            // Update state with actual data source used
            if actual_type != source_type {
                state.set_active_data_source(actual_type);
            }

            match spawn_collector_with_source(state.clone(), event_tx.clone(), data_source) {
                Ok(handle) => Some(handle),
                Err(e) => {
                    eprintln!("Warning: Could not start data collector: {}", e);
                    eprintln!("Running in demo mode");
                    None
                }
            }
        }
        Err(e) => {
            eprintln!("Warning: Could not create data source: {}", e);
            eprintln!("Running in demo mode - no data source available");
            None
        }
    };

    // Spawn input handler
    spawn_input_handler(event_tx.clone());

    // Create dashboard
    let mut dashboard = Dashboard::new(state.clone());

    // Wrap collector handle in Arc<Mutex> for sharing
    let collector_handle = Arc::new(Mutex::new(collector_handle));

    // Run main event loop
    let result = run_event_loop(&mut terminal, &mut dashboard, event_rx, event_tx, state.clone(), collector_handle.clone()).await;

    // Cleanup
    restore_terminal(&mut terminal)?;

    // Abort background tasks if they exist
    if let Some(handle) = collector_handle.lock().unwrap().take() {
        handle.abort();
    }

    result
}

fn parse_args() -> AppConfig {
    let matches = Command::new("q-status")
        .version("0.1.0")
        .author("Q-Status Team")
        .about("High-performance token usage monitor for Amazon Q and Claude Code")
        .arg(
            Arg::new("refresh-rate")
                .short('r')
                .long("refresh-rate")
                .value_name("SECONDS")
                .help("Refresh rate in seconds")
                .default_value("2"),
        )
        .arg(
            Arg::new("config")
                .short('c')
                .long("config")
                .value_name("FILE")
                .help("Path to configuration file"),
        )
        .arg(
            Arg::new("data-source")
                .short('s')
                .long("data-source")
                .value_name("SOURCE")
                .help("Data source to use (amazon-q, claude-code)")
                .value_parser(["amazon-q", "claude-code", "claude", "q"]),
        )
        .arg(
            Arg::new("debug")
                .short('d')
                .long("debug")
                .help("Enable debug logging")
                .action(ArgAction::SetTrue),
        )
        .get_matches();

    // Load config from file and environment variables first
    let mut config = AppConfig::load();

    if let Some(rate) = matches.get_one::<String>("refresh-rate") {
        if let Ok(parsed) = rate.parse() {
            config.refresh_rate = parsed;
        }
    }

    if let Some(config_path) = matches.get_one::<String>("config") {
        config.config_path = Some(config_path.into());
    }

    config.debug = matches.get_flag("debug");

    if let Some(source) = matches.get_one::<String>("data-source") {
        config.data_source = source.clone();
    }

    config
}

fn setup_terminal() -> Result<Terminal<CrosstermBackend<io::Stdout>>> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    Ok(Terminal::new(backend)?)
}

fn restore_terminal(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>) -> Result<()> {
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
    std::thread::spawn(move || loop {
        if event::poll(Duration::from_millis(100)).unwrap() {
            if let Ok(Event::Key(key)) = event::read() {
                let _ = tx.send(AppEvent::Input(key));
            }
        }
    });
}

async fn run_event_loop(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    dashboard: &mut Dashboard,
    event_rx: Receiver<AppEvent>,
    event_tx: Sender<AppEvent>,
    state: Arc<AppState>,
    collector_handle: Arc<Mutex<Option<JoinHandle<()>>>>,
) -> Result<()> {
    loop {
        // Render dashboard
        terminal.draw(|f| dashboard.render(f))?;

        // Handle events with timeout
        if let Ok(event) = event_rx.recv_timeout(Duration::from_millis(50)) {
            match event {
                AppEvent::Input(key) => {
                    if !dashboard.handle_key(key.code) {
                        break; // Quit requested
                    }

                    // Check if provider switch was requested
                    if dashboard.is_switching_provider() {
                        // Handle provider switching
                        let current_source = state.get_active_data_source();
                        let new_source = match current_source {
                            q_status::data::DataSourceType::AmazonQ => q_status::data::DataSourceType::ClaudeCode,
                            q_status::data::DataSourceType::ClaudeCode => q_status::data::DataSourceType::AmazonQ,
                        };

                        // Abort the current collector
                        if let Some(handle) = collector_handle.lock().unwrap().take() {
                            handle.abort();
                        }

                        // Try to create new data source
                        match q_status::data::DataSourceFactory::create(new_source, state.config.cost_per_1k_tokens) {
                            Ok(data_source) => {
                                // Spawn new collector with new data source
                                match q_status::data::spawn_collector_with_datasource(
                                    state.clone(),
                                    event_tx.clone(),
                                    data_source,
                                ) {
                                    Ok(new_handle) => {
                                        // Update state with new data source
                                        state.set_active_data_source(new_source);
                                        // Store new collector handle
                                        *collector_handle.lock().unwrap() = Some(new_handle);
                                        eprintln!("Switched to {}", new_source.display_name());
                                    }
                                    Err(e) => {
                                        eprintln!("Failed to start collector for {}: {}", new_source.display_name(), e);
                                    }
                                }
                            }
                            Err(e) => {
                                eprintln!("Failed to create {}: {}", new_source.display_name(), e);
                            }
                        }

                        // Reset the switching flag
                        dashboard.reset_switching_flag();
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

// Helper function to spawn collector with a specific data source
fn spawn_collector_with_source(
    state: Arc<AppState>,
    event_tx: Sender<AppEvent>,
    data_source: Box<dyn q_status::data::DataSource>,
) -> Result<tokio::task::JoinHandle<()>> {
    use q_status::data::DataCollector;

    let collector = DataCollector::new(state, data_source, event_tx)?;
    let handle = tokio::spawn(async move {
        collector.run().await;
    });
    Ok(handle)
}

async fn run_status_check(state: Arc<AppState>) -> Result<()> {
    use q_status::data::{DataSourceFactory, DataSourceType};

    let source_type = DataSourceType::from_str(&state.config.data_source)
        .unwrap_or(DataSourceType::AmazonQ);

    println!("Q-Status Monitor - {} System Overview", source_type.display_name());
    println!("==========================================");

    // Try to connect to appropriate data source
    match DataSourceFactory::create_with_fallback(source_type, state.config.cost_per_1k_tokens) {
        Ok((mut data_source, actual_type)) => {
            if actual_type != source_type {
                println!("Note: Using {} (requested {} not available)", actual_type, source_type);
            } else {
                println!("✓ Connected to {} data source", actual_type);
            }
            println!();
            
            // Get global statistics
            let global_stats = futures::executor::block_on(
                data_source.get_global_stats(state.config.cost_per_1k_tokens)
            )?;
            println!("📊 System-Wide Statistics:");
            println!("  - Total Conversations: {}", global_stats.total_conversations);
            println!("  - Total Tokens Used: {}", global_stats.total_tokens);
            println!("  - Average per Conversation: {} tokens", global_stats.average_tokens);
            println!("  - Conversations at Warning: {} (70-90%)", global_stats.conversations_warning);
            println!("  - Conversations Critical: {} (90%+)", global_stats.conversations_critical);
            println!("  - Total Estimated Cost: ${:.2}", global_stats.total_cost_estimate);
            println!();
            
            // Get all conversation summaries
            let summaries = futures::executor::block_on(
                data_source.get_all_conversation_summaries()
            )?;
            println!("🔝 Top Conversations by Token Usage:");
            for (idx, conv) in summaries.iter().take(5).enumerate() {
                let status_emoji = match conv.token_usage.compaction_status {
                    q_status::data::database::CompactionStatus::Safe => "🟢",
                    q_status::data::database::CompactionStatus::Warning => "🟡",
                    q_status::data::database::CompactionStatus::Critical => "🟠",
                    q_status::data::database::CompactionStatus::Imminent => "🔴",
                };
                let path_display = if conv.path.len() > 50 {
                    format!("...{}", &conv.path[conv.path.len()-47..])
                } else {
                    conv.path.clone()
                };
                println!("  {}. {} {} - {} tokens ({:.1}%)", 
                    idx + 1,
                    status_emoji,
                    path_display,
                    conv.token_usage.total_tokens,
                    conv.token_usage.percentage
                );
            }
            println!();
            
            // Get latest conversation (most recently modified)
            println!("📍 Latest Conversation:");
            match futures::executor::block_on(
                data_source.get_current_conversation(None)
            ) {
                Ok(Some(conv)) => {
                    let usage_details = futures::executor::block_on(
                        data_source.get_token_usage(&conv)
                    )?;
                    println!("✓ Active conversation found");
                    println!("  - Conversation ID: {}", conv.conversation_id);
                    println!("  - Message count: {} exchanges", usage_details.message_count);
                    println!("  - Conversation tokens: {}", usage_details.history_tokens);
                    println!("  - Context tokens: {}", usage_details.context_tokens);
                    println!("  - Total tokens: {} / {} ({:.1}%)", 
                        usage_details.total_tokens, 
                        usage_details.context_window, 
                        usage_details.percentage);
                    println!("  - Note: Using 175K effective limit (safer than 200K actual)");
                    
                    // Show compaction status
                    let status_emoji = match usage_details.compaction_status {
                        q_status::data::database::CompactionStatus::Safe => "🟢",
                        q_status::data::database::CompactionStatus::Warning => "🟡",
                        q_status::data::database::CompactionStatus::Critical => "🟠",
                        q_status::data::database::CompactionStatus::Imminent => "🔴",
                    };
                    println!("  - Compaction status: {} {:?}", status_emoji, usage_details.compaction_status);
                    
                    // Calculate costs
                    let cost_per_1k = state.config.cost_per_1k_tokens;
                    let session_cost = (usage_details.total_tokens as f64 / 1000.0) * cost_per_1k;
                    println!("  - Estimated session cost: ${:.4}", session_cost);
                }
                Ok(None) => {
                    println!("! No conversations found in the database");
                    println!("  Start using Q to see activity here");
                }
                Err(e) => {
                    println!("✗ Error reading conversation: {}", e);
                }
            }
            
            // Check if data source has recent changes
            match futures::executor::block_on(
                data_source.has_changed()
            ) {
                Ok(changed) => {
                    if changed {
                        println!("✓ Data source has recent activity");
                    } else {
                        println!("  Data source is idle");
                    }
                }
                Err(e) => {
                    println!("✗ Error checking data source status: {}", e);
                }
            }
        }
        Err(e) => {
            println!("✗ Data source not available: {}", e);
            println!();
            println!("Expected locations:");
            if source_type == DataSourceType::AmazonQ {
                println!("  Amazon Q:");
                println!("    - ~/Library/Application Support/amazon-q/data.sqlite3 (macOS)");
                println!("    - ~/.local/share/amazon-q/data.sqlite3 (Linux)");
                println!("    - ~/.aws/q/db/q.db (Legacy)");
            } else {
                println!("  Claude Code:");
                println!("    - ~/.claude/usage/*.json (usage files)");
            }
            println!();
            println!("Make sure {} is installed and has been used at least once.", source_type);
        }
    }
    
    println!();
    println!("Note: Run q-status in a terminal for the full interactive dashboard.");
    
    Ok(())
}
