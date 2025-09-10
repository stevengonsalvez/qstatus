// ABOUTME: Entry point for Q-Status Monitor application
// Sets up terminal, event loop, and coordinates all components

use anyhow::Result;
use clap::{Arg, Command};
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
    data::collector::spawn_collector,
    ui::dashboard::Dashboard,
};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::io;
use std::sync::Arc;
use std::time::Duration;

#[tokio::main]
async fn main() -> Result<()> {
    // Parse CLI arguments
    let config = parse_args();

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

    // Try to spawn data collector - if database not found, still run UI
    let collector_handle = match spawn_collector(state.clone(), event_tx.clone()) {
        Ok(handle) => Some(handle),
        Err(e) => {
            eprintln!("Warning: Could not start data collector: {}", e);
            eprintln!("Running in demo mode - Q database not found");
            None
        }
    };

    // Spawn input handler
    spawn_input_handler(event_tx.clone());

    // Create dashboard
    let mut dashboard = Dashboard::new(state.clone());

    // Run main event loop
    let result = run_event_loop(&mut terminal, &mut dashboard, event_rx).await;

    // Cleanup
    restore_terminal(&mut terminal)?;

    // Abort background tasks if they exist
    if let Some(handle) = collector_handle {
        handle.abort();
    }

    result
}

fn parse_args() -> AppConfig {
    let matches = Command::new("q-status")
        .version("0.1.0")
        .author("Q-Status Team")
        .about("High-performance token usage monitor for Amazon Q CLI")
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
            Arg::new("debug")
                .short('d')
                .long("debug")
                .help("Enable debug logging")
                .action(clap::ArgAction::SetTrue),
        )
        .get_matches();

    let mut config = AppConfig::default();

    if let Some(rate) = matches.get_one::<String>("refresh-rate") {
        if let Ok(parsed) = rate.parse() {
            config.refresh_rate = parsed;
        }
    }

    if let Some(config_path) = matches.get_one::<String>("config") {
        config.config_path = Some(config_path.into());
    }

    config.debug = matches.get_flag("debug");

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

async fn run_status_check(state: Arc<AppState>) -> Result<()> {
    use q_status::data::database::QDatabase;
    
    println!("Q-Status Monitor - Global System Overview");
    println!("==========================================");
    
    // Try to connect to database
    match QDatabase::new() {
        Ok(mut db) => {
            println!("✓ Q database found at: {:?}", db.db_path);
            println!();
            
            // Get global statistics
            let global_stats = db.get_global_stats(state.config.cost_per_1k_tokens)?;
            println!("📊 System-Wide Statistics:");
            println!("  - Total Conversations: {}", global_stats.total_conversations);
            println!("  - Total Tokens Used: {}", global_stats.total_tokens);
            println!("  - Average per Conversation: {} tokens", global_stats.average_tokens);
            println!("  - Conversations at Warning: {} (70-90%)", global_stats.conversations_warning);
            println!("  - Conversations Critical: {} (90%+)", global_stats.conversations_critical);
            println!("  - Total Estimated Cost: ${:.2}", global_stats.total_cost_estimate);
            println!();
            
            // Get all conversation summaries
            let summaries = db.get_all_conversation_summaries()?;
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
            
            // Get current directory conversation if it exists
            println!("📍 Current Directory:");
            match db.get_current_conversation(None) {
                Ok(Some(conv)) => {
                    let usage_details = db.get_token_usage(&conv);
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
                    println!("! No active conversation in current directory");
                    println!("  Try running from a directory where you've used Q");
                }
                Err(e) => {
                    println!("✗ Error reading conversation: {}", e);
                }
            }
            
            // Check if database has recent changes
            match db.has_changed() {
                Ok(changed) => {
                    if changed {
                        println!("✓ Database has recent activity");
                    } else {
                        println!("  Database is idle");
                    }
                }
                Err(e) => {
                    println!("✗ Error checking database status: {}", e);
                }
            }
        }
        Err(e) => {
            println!("✗ Q database not found: {}", e);
            println!();
            println!("Expected locations:");
            println!("  - ~/Library/Application Support/amazon-q/data.sqlite3 (macOS)");
            println!("  - ~/.local/share/amazon-q/data.sqlite3 (Linux)");
            println!("  - ~/.aws/q/db/q.db (Legacy)");
            println!();
            println!("Make sure Amazon Q CLI is installed and has been used at least once.");
        }
    }
    
    println!();
    println!("Note: Run q-status in a terminal for the full interactive dashboard.");
    
    Ok(())
}
