// ABOUTME: Main dashboard layout and rendering logic
// Implements the primary UI following Ratatui best practices

use crate::app::state::AppState;
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Gauge, Paragraph, List, ListItem, ListState},
    Frame,
};
use std::sync::Arc;

pub struct Dashboard {
    state: Arc<AppState>,
    show_help: bool,
    switching_provider: bool,
}

impl Dashboard {
    pub fn new(state: Arc<AppState>) -> Self {
        Self {
            state,
            show_help: false,
            switching_provider: false,
        }
    }

    pub fn render(&self, frame: &mut Frame) {
        let size = frame.size();

        // Main layout: header, body, footer
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Header
                Constraint::Min(0),    // Body
                Constraint::Length(3), // Footer
            ])
            .split(size);

        self.render_header(frame, chunks[0]);
        self.render_body(frame, chunks[1]);
        self.render_footer(frame, chunks[2]);

        // Overlay help if requested
        if self.show_help {
            self.render_help_overlay(frame, size);
        }
    }

    fn render_header(&self, frame: &mut Frame, area: Rect) {
        let is_connected = *self.state.is_connected.lock().unwrap();
        let data_source = self.state.get_active_data_source();

        let status = if self.switching_provider {
            "Switching..."
        } else if is_connected {
            "Connected"
        } else {
            "Disconnected"
        };
        let status_color = if self.switching_provider {
            Color::Yellow
        } else if is_connected {
            Color::Green
        } else {
            Color::Red
        };

        let header_text = vec![
            Span::styled(
                "Q-Status Monitor",
                Style::default().add_modifier(Modifier::BOLD),
            ),
            Span::raw(" v0.3.0  ["),
            Span::styled(
                data_source.display_name(),
                Style::default().fg(Color::Cyan),
            ),
            Span::raw("] ["),
            Span::styled(status, Style::default().fg(status_color)),
            Span::raw("]"),
        ];

        let header = Paragraph::new(Line::from(header_text))
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::Blue)),
            )
            .alignment(Alignment::Center);

        frame.render_widget(header, area);
    }

    fn render_body(&self, frame: &mut Frame, area: Rect) {
        let view_mode = self.state.view_mode.lock().unwrap().clone();
        
        match view_mode {
            crate::app::state::ViewMode::GlobalOverview => {
                self.render_global_overview(frame, area);
            }
            crate::app::state::ViewMode::CurrentDirectory => {
                let data_source = self.state.get_active_data_source();

                // Add active session display for Claude mode
                if matches!(data_source, crate::data::DataSourceType::ClaudeCode) {
                    if let Some(_session) = self.state.get_active_claude_session() {
                        // Layout with active session display
                        let chunks = Layout::default()
                            .direction(Direction::Vertical)
                            .constraints([
                                Constraint::Length(5),  // Active session
                                Constraint::Length(6),  // Token usage gauge
                                Constraint::Length(4),  // Cost analysis
                                Constraint::Min(10),    // Session details
                            ])
                            .split(area);

                        self.render_active_session(frame, chunks[0]);
                        self.render_token_gauge(frame, chunks[1]);
                        self.render_cost_panel(frame, chunks[2]);
                        self.render_usage_info(frame, chunks[3]);
                    } else {
                        // No active session - standard layout
                        let chunks = Layout::default()
                            .direction(Direction::Vertical)
                            .constraints([
                                Constraint::Length(6),  // Token usage gauge
                                Constraint::Length(4),  // Cost analysis
                                Constraint::Min(10),    // Session details
                            ])
                            .split(area);

                        self.render_token_gauge(frame, chunks[0]);
                        self.render_cost_panel(frame, chunks[1]);
                        self.render_usage_info(frame, chunks[2]);
                    }
                } else {
                    // Non-Claude mode - standard layout
                    let chunks = Layout::default()
                        .direction(Direction::Vertical)
                        .constraints([
                            Constraint::Length(6),  // Token usage gauge
                            Constraint::Length(4),  // Cost analysis
                            Constraint::Min(10),    // Session details
                        ])
                        .split(area);

                    self.render_token_gauge(frame, chunks[0]);
                    self.render_cost_panel(frame, chunks[1]);
                    self.render_usage_info(frame, chunks[2]);
                }
            }
            crate::app::state::ViewMode::ConversationList => {
                self.render_conversation_list(frame, area);
            }
            crate::app::state::ViewMode::SessionList => {
                self.render_session_list(frame, area);
            }
            crate::app::state::ViewMode::SessionDetail => {
                self.render_session_detail(frame, area);
            }
        }
    }

    fn render_token_gauge(&self, frame: &mut Frame, area: Rect) {
        let usage = self.state.token_usage.lock().unwrap();
        let percentage = usage.percentage;  // Already capped in database.rs
        let color = self.get_usage_color(percentage);

        let data_source = self.state.get_active_data_source();

        // Get compaction status indicator
        let status_indicator = match usage.compaction_status {
            crate::data::database::CompactionStatus::Safe => "🟢",
            crate::data::database::CompactionStatus::Warning => "🟡",
            crate::data::database::CompactionStatus::Critical => "🟠",
            crate::data::database::CompactionStatus::Imminent => "🔴",
        };

        // Adjust title based on data source
        let title = if matches!(data_source, crate::data::DataSourceType::ClaudeCode) {
            let limit = self.state.config.claude_token_limit;
            format!("Token Usage - {} Limit {}",
                if limit >= 1_000_000 {
                    format!("{}M", limit / 1_000_000)
                } else if limit >= 1_000 {
                    format!("{}K", limit / 1_000)
                } else {
                    format!("{}", limit)
                },
                status_indicator
            )
        } else {
            format!("Token Usage - 175K Effective Limit {}", status_indicator)
        };

        // Add warning emoji if over threshold for Claude
        let mut label = format!(
            "{} / {} tokens ({:.1}%)",
            usage.used, usage.context_window, percentage
        );

        if matches!(data_source, crate::data::DataSourceType::ClaudeCode) {
            let warning_threshold = self.state.config.claude_warning_threshold * 100.0;
            if percentage >= warning_threshold {
                label = format!("⚠️  {} / {} tokens ({:.1}%)",
                    usage.used, usage.context_window, percentage);
            }
        }

        let gauge = Gauge::default()
            .block(
                Block::default()
                    .title(title)
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(color)),
            )
            .gauge_style(Style::default().fg(color))
            .percent(percentage as u16)
            .label(label);

        frame.render_widget(gauge, area);
    }

    fn render_active_session(&self, frame: &mut Frame, area: Rect) {
        let data_source = self.state.get_active_data_source();

        if !matches!(data_source, crate::data::DataSourceType::ClaudeCode) {
            return;
        }

        if let Some(session) = self.state.get_active_claude_session() {
            let duration = (session.end_time - session.start_time).num_minutes();

            // Get context tokens (current memory) and total tokens (cumulative)
            let context_tokens = session.context_tokens.as_ref()
                .map(|ct| ct.total())
                .unwrap_or_else(|| session.total_tokens.total());
            let cumulative_tokens = session.total_tokens.total();

            // Show actual cost from cost_usd when available
            let cost_text = if session.cost_breakdown.percent_actual > 0.0 {
                format!("${:.4} ({}% actual)", session.total_cost, session.cost_breakdown.percent_actual as u32)
            } else {
                format!("${:.4} (estimated)", session.total_cost)
            };

            let text = vec![
                Line::from(vec![
                    Span::styled("🔴 Active Session: ", Style::default().fg(Color::Red).add_modifier(Modifier::BOLD)),
                    Span::raw(&session.id[..8.min(session.id.len())]),
                    Span::raw(" | "),
                    Span::styled("Context: ", Style::default().fg(Color::Cyan)),
                    Span::styled(format!("{} tokens", context_tokens), Style::default().fg(Color::Yellow)),
                    Span::raw(" | "),
                    Span::styled("Total: ", Style::default().fg(Color::Cyan)),
                    Span::styled(format!("{} tokens", cumulative_tokens), Style::default().fg(Color::Yellow)),
                    Span::raw(" | "),
                    Span::styled(cost_text, Style::default().fg(Color::Green)),
                    Span::raw(" | "),
                    Span::raw(format!("{}m ago", duration)),
                ]),
            ];

            let active_panel = Paragraph::new(text)
                .block(
                    Block::default()
                        .title("Claude Code - Active Session (Last 5 Hours)")
                        .borders(Borders::ALL)
                        .border_style(Style::default().fg(Color::Magenta)),
                )
                .alignment(Alignment::Center);

            frame.render_widget(active_panel, area);
        }
    }

    fn render_cost_panel(&self, frame: &mut Frame, area: Rect) {
        let cost = self.state.cost_analysis.lock().unwrap();

        let cost_text = format!(
            "Session: ${:.2} | Today: ${:.2} | Month: ${:.2}",
            cost.session_cost, cost.daily_cost, cost.monthly_cost
        );

        let cost_panel = Paragraph::new(cost_text)
            .block(
                Block::default()
                    .title("Cost Analysis")
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::Yellow)),
            )
            .alignment(Alignment::Center);

        frame.render_widget(cost_panel, area);
    }

    fn render_usage_info(&self, frame: &mut Frame, area: Rect) {
        let usage = self.state.token_usage.lock().unwrap();
        let conversation_id = self.state.current_conversation.lock().unwrap();
        let data_source = self.state.get_active_data_source();

        let mut text = vec![];

        // Show conversation ID if present
        if let Some(ref id) = *conversation_id {
            text.push(Line::from(format!("Session ID: {}", id)));
        } else {
            text.push(Line::from("No active conversation in this directory"));
        }

        // Token breakdown
        text.push(Line::from(""));
        text.push(Line::from(Span::styled(
            "Token Breakdown (Current Context):",
            Style::default().add_modifier(Modifier::BOLD),
        )));
        text.push(Line::from(format!(
            "  Cache Read: {} tokens",
            usage.history_tokens
        )));
        text.push(Line::from(format!(
            "  Cache Creation: {} tokens",
            usage.context_tokens
        )));
        text.push(Line::from(format!(
            "  Total Context: {} / {} ({:.1}%)",
            usage.used, usage.context_window, usage.percentage
        )));

        // Add cumulative total for Claude sessions
        if matches!(data_source, crate::data::DataSourceType::ClaudeCode) {
            if let Some(session) = self.state.get_active_claude_session() {
                let cumulative = session.total_tokens.total();
                text.push(Line::from(""));
                text.push(Line::from(Span::styled(
                    "Cumulative Usage (All Messages):",
                    Style::default().add_modifier(Modifier::BOLD),
                )));
                text.push(Line::from(format!(
                    "  Total Tokens: {} (for billing)",
                    cumulative
                )));
            }
        }
        
        // Compaction info
        text.push(Line::from(""));
        text.push(Line::from(Span::styled(
            "Compaction Status:",
            Style::default().add_modifier(Modifier::BOLD),
        )));
        
        let compaction_text = match usage.compaction_status {
            crate::data::database::CompactionStatus::Safe => {
                format!("Safe - {:.0} tokens until warning", 
                    (usage.context_window as f64 * 0.7) - usage.used as f64)
            },
            crate::data::database::CompactionStatus::Warning => {
                format!("Warning - {:.0} tokens until critical",
                    (usage.context_window as f64 * 0.9) - usage.used as f64)
            },
            crate::data::database::CompactionStatus::Critical => {
                format!("Critical - {:.0} tokens until compaction",
                    (usage.context_window as f64 * 0.95) - usage.used as f64)
            },
            crate::data::database::CompactionStatus::Imminent => {
                "Imminent - Compaction will trigger soon".to_string()
            },
        };
        text.push(Line::from(format!("  {}", compaction_text)));
        
        if usage.has_summary {
            text.push(Line::from("  ℹ️  Previous compaction detected"));
        }
        
        // Message stats
        text.push(Line::from(""));
        text.push(Line::from(format!(
            "Messages: {} exchanges",
            usage.message_count
        )));
        if usage.message_count > 0 {
            text.push(Line::from(format!(
                "Avg per message: {} tokens",
                usage.used / usage.message_count as u64
            )));
        }

        let info = Paragraph::new(text).block(
            Block::default()
                .title("Session Details")
                .borders(Borders::ALL),
        );

        frame.render_widget(info, area);
    }

    fn render_global_overview(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(8),  // Global stats
                Constraint::Min(10),    // Top conversations
            ])
            .split(area);

        // Render global statistics
        self.render_global_stats(frame, chunks[0]);
        // Render top conversations
        self.render_top_conversations(frame, chunks[1]);
    }
    
    fn render_global_stats(&self, frame: &mut Frame, area: Rect) {
        let global_stats = self.state.global_stats.lock().unwrap();
        
        let mut text = vec![];
        
        if let Some(ref stats) = *global_stats {
            text.push(Line::from(vec![
                Span::raw("Total Conversations: "),
                Span::styled(
                    format!("{}", stats.total_conversations),
                    Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD),
                ),
            ]));
            
            text.push(Line::from(vec![
                Span::raw("Total Tokens: "),
                Span::styled(
                    format!("{}", stats.total_tokens),
                    Style::default().fg(Color::Yellow),
                ),
                Span::raw(" | Average: "),
                Span::styled(
                    format!("{}", stats.average_tokens),
                    Style::default().fg(Color::Yellow),
                ),
            ]));
            
            text.push(Line::from(vec![
                Span::raw("Conversations needing attention: "),
                Span::styled(
                    format!("{} warning", stats.conversations_warning),
                    Style::default().fg(Color::Yellow),
                ),
                Span::raw(", "),
                Span::styled(
                    format!("{} critical", stats.conversations_critical),
                    Style::default().fg(Color::Red),
                ),
            ]));
            
            text.push(Line::from(vec![
                Span::raw("Total Estimated Cost: "),
                Span::styled(
                    format!("${:.2}", stats.total_cost_estimate),
                    Style::default().fg(Color::Green).add_modifier(Modifier::BOLD),
                ),
            ]));
        } else {
            text.push(Line::from("Loading global statistics..."));
        }
        
        let stats_panel = Paragraph::new(text)
            .block(
                Block::default()
                    .title("System-Wide Q Usage Statistics")
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::Magenta)),
            );
            
        frame.render_widget(stats_panel, area);
    }
    
    fn render_top_conversations(&self, frame: &mut Frame, area: Rect) {
        let conversations = self.state.all_conversations.lock().unwrap();
        let current_dir = std::env::current_dir().unwrap_or_default();
        let current_dir_str = current_dir.to_string_lossy();
        
        let mut text = vec![];
        
        // Header row
        text.push(Line::from(vec![
            Span::styled(
                "Path",
                Style::default().add_modifier(Modifier::BOLD | Modifier::UNDERLINED),
            ),
            Span::raw("                                        "),
            Span::styled(
                "Tokens",
                Style::default().add_modifier(Modifier::BOLD | Modifier::UNDERLINED),
            ),
            Span::raw("     "),
            Span::styled(
                "Status",
                Style::default().add_modifier(Modifier::BOLD | Modifier::UNDERLINED),
            ),
        ]));
        
        text.push(Line::from("")); // Empty line
        
        // Show top 10 conversations
        for (idx, conv) in conversations.iter().take(10).enumerate() {
            let path_display = if conv.path.len() > 40 {
                format!("...{}", &conv.path[conv.path.len()-37..])
            } else {
                conv.path.clone()
            };
            
            let is_current = conv.path == current_dir_str;
            let status_emoji = match conv.token_usage.compaction_status {
                crate::data::database::CompactionStatus::Safe => "🟢",
                crate::data::database::CompactionStatus::Warning => "🟡",
                crate::data::database::CompactionStatus::Critical => "🟠",
                crate::data::database::CompactionStatus::Imminent => "🔴",
            };
            
            let style = if is_current {
                Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)
            } else {
                Style::default()
            };
            
            text.push(Line::from(vec![
                Span::styled(
                    format!("{:2}. {:40}", idx + 1, path_display),
                    style,
                ),
                Span::styled(
                    format!("{:>8} ({:>5.1}%)",
                        conv.token_usage.total_tokens,
                        conv.token_usage.percentage
                    ),
                    style,
                ),
                Span::raw("  "),
                Span::raw(status_emoji),
            ]));
        }
        
        let list_panel = Paragraph::new(text)
            .block(
                Block::default()
                    .title("Top Conversations by Token Usage")
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::Blue)),
            );
            
        frame.render_widget(list_panel, area);
    }
    
    fn render_conversation_list(&self, frame: &mut Frame, area: Rect) {
        let conversations = self.state.all_conversations.lock().unwrap();
        let selected_idx = *self.state.selected_conversation_index.lock().unwrap();
        
        let mut text = vec![];
        text.push(Line::from("All Conversations (↑↓ to navigate, Enter to view):"));
        text.push(Line::from(""));
        
        for (idx, conv) in conversations.iter().enumerate() {
            let is_selected = idx == selected_idx;
            let style = if is_selected {
                Style::default().bg(Color::Gray).fg(Color::Black)
            } else {
                Style::default()
            };
            
            text.push(Line::from(Span::styled(
                format!("{} - {} tokens", conv.path, conv.token_usage.total_tokens),
                style,
            )));
        }
        
        let list = Paragraph::new(text)
            .block(
                Block::default()
                    .title("Conversation List")
                    .borders(Borders::ALL),
            );
            
        frame.render_widget(list, area);
    }
    
    fn render_session_list(&self, frame: &mut Frame, area: Rect) {
        // Split layout: Session list on top, metrics widget at bottom
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Min(10),    // Session list
                Constraint::Length(8),  // Metrics widget
            ])
            .split(area);
        
        // Split the session list area into header and list
        let list_chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(4),  // Header
                Constraint::Min(5),     // List content
            ])
            .split(chunks[0]);
        
        // Render header
        let directory_groups = self.state.directory_groups.lock().unwrap();
        let show_active_only = *self.state.show_active_only.lock().unwrap();
        let selected_idx = *self.state.selected_conversation_index.lock().unwrap();
        let last_refresh = *self.state.last_refresh.lock().unwrap();
        
        let header_text = vec![
            Line::from(Span::styled(
                format!(
                    "Sessions (Active: {} | Showing: {}/{}) - Last refresh: {}",
                    if show_active_only { "ON" } else { "OFF" },
                    if show_active_only {
                        directory_groups.iter().map(|g| g.active_session_count).sum::<usize>()
                    } else {
                        directory_groups.iter().map(|g| g.sessions.len()).sum::<usize>()
                    },
                    directory_groups.iter().map(|g| g.sessions.len()).sum::<usize>(),
                    last_refresh.format("%H:%M:%S")
                ),
                Style::default().add_modifier(Modifier::BOLD),
            )),
            Line::from("[A] Toggle Active | [↑↓] Navigate | [Enter] View Details"),
            Line::from("Icons: 🟢 Active (dir modified <7 days) | ⚫ Inactive | 📎 Has Context Files"),
        ];
        
        let header = Paragraph::new(header_text)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(header, list_chunks[0]);
        
        // Build visible sessions list
        let mut items = Vec::new();
        let mut visible_sessions = Vec::new();
        
        for group in directory_groups.iter() {
            if show_active_only && group.active_session_count == 0 {
                continue;
            }
            
            // Add directory header
            let has_visible_sessions = group.sessions.iter()
                .any(|s| !show_active_only || s.is_active);
                
            if has_visible_sessions {
                items.push(ListItem::new(Line::from(Span::styled(
                    format!("📁 {} ({} sessions)", group.directory, 
                        if show_active_only { group.active_session_count } else { group.sessions.len() }),
                    Style::default().fg(Color::DarkGray),
                ))));
                
                // Add sessions
                for session in &group.sessions {
                    if show_active_only && !session.is_active {
                        continue;
                    }
                    
                    visible_sessions.push(session.clone());
                    let session_idx = visible_sessions.len() - 1;
                    
                    let status_icon = if session.is_active { "🟢" } else { "⚫" };
                    let context_icon = if session.has_active_context { "📎" } else { "  " };
                    // Show session cost (current conversation cost)
                    // Note: Amazon Q stores only one conversation per folder, so cumulative = current
                    let cost_text = format!("${:.4}", session.session_cost);
                    
                    // Show percentage of context window used (how much room left)
                    let window_pct = session.token_usage.percentage;
                    
                    // Add visual indicator for context window usage
                    let usage_indicator = if window_pct > 90.0 {
                        "🔴"  // Critical - almost full
                    } else if window_pct > 70.0 {
                        "🟡"  // Warning - getting full
                    } else {
                        ""    // Plenty of room
                    };
                    
                    // Safely get conversation ID substring
                    let conv_id = if session.conversation_id.len() >= 8 {
                        &session.conversation_id[..8]
                    } else {
                        &session.conversation_id
                    };
                    
                    let session_text = format!(
                        "  {} {} {} | {}/{} ({:.1}% used) {} | {} msgs | {}",
                        status_icon,
                        context_icon,
                        conv_id,
                        session.token_usage.total_tokens,
                        session.token_usage.context_window,
                        if window_pct >= 100.0 { 100.0 } else if window_pct > 99.9 { 99.9 } else { window_pct },
                        usage_indicator,
                        session.message_count,
                        cost_text
                    );
                    
                    // Highlight selected item
                    let style = if session_idx == selected_idx {
                        Style::default()
                            .bg(Color::Rgb(70, 70, 70))
                            .fg(Color::Rgb(255, 255, 255))
                            .add_modifier(Modifier::BOLD)
                    } else {
                        Style::default().fg(Color::Rgb(200, 200, 200))
                    };
                    
                    items.push(ListItem::new(Line::from(Span::styled(session_text, style))));
                }
            }
        }
        
        // Create list widget with proper state for scrolling
        let mut list_state = ListState::default();
        
        // Calculate the actual index in the items list (accounting for headers)
        let mut actual_idx = 0;
        let mut session_count = 0;
        for (i, item) in items.iter().enumerate() {
            // Check if this is a session item (starts with spaces)
            let item_text = format!("{:?}", item);
            if item_text.contains("  🟢") || item_text.contains("  ⚫") {
                if session_count == selected_idx {
                    actual_idx = i;
                    break;
                }
                session_count += 1;
            }
        }
        
        list_state.select(Some(actual_idx));
        
        let list = List::new(items)
            .block(
                Block::default()
                    .title("Session List")
                    .borders(Borders::ALL),
            )
            .highlight_style(Style::default())  // No additional highlight since we style items
            .highlight_symbol("▶ ");
            
        frame.render_stateful_widget(list, list_chunks[1], &mut list_state);
        
        // Render metrics widget at bottom
        self.render_metrics_widget(frame, chunks[1]);
    }
    
    fn render_session_detail(&self, frame: &mut Frame, area: Rect) {
        let selected_session = self.state.selected_session.lock().unwrap();
        
        if let Some(ref session) = *selected_session {
            let mut text = vec![];
            
            // Session header
            text.push(Line::from(Span::styled(
                format!("Session: {}", session.conversation_id),
                Style::default().add_modifier(Modifier::BOLD).fg(Color::Cyan),
            )));
            text.push(Line::from(format!("Directory: {}", session.directory)));
            text.push(Line::from(format!(
                "Last Activity: {}",
                session.last_activity.format("%Y-%m-%d %H:%M:%S")
            )));
            text.push(Line::from(""));
            
            // Token usage details
            text.push(Line::from(Span::styled(
                "Token Usage:",
                Style::default().add_modifier(Modifier::BOLD),
            )));
            text.push(Line::from(format!(
                "  Conversation: {} tokens",
                session.token_usage.history_tokens
            )));
            text.push(Line::from(format!(
                "  Context: {} tokens",
                session.token_usage.context_tokens
            )));
            text.push(Line::from(format!(
                "  Total: {} / {} ({:.1}% used)",
                session.token_usage.total_tokens,
                session.token_usage.context_window,
                session.token_usage.percentage  // Already capped in database.rs
            )));
            
            let remaining = session.token_usage.context_window.saturating_sub(session.token_usage.total_tokens);
            let remaining_pct = if session.token_usage.percentage >= 100.0 {
                0.0
            } else {
                100.0 - session.token_usage.percentage
            };
            text.push(Line::from(format!(
                "  Remaining: {} tokens ({:.1}% available)",
                remaining,
                remaining_pct
            )));
            
            // Compaction status
            text.push(Line::from(""));
            text.push(Line::from(Span::styled(
                "Compaction Status:",
                Style::default().add_modifier(Modifier::BOLD),
            )));
            let status_text = match session.token_usage.compaction_status {
                crate::data::database::CompactionStatus::Safe => "🟢 Safe",
                crate::data::database::CompactionStatus::Warning => "🟡 Warning",
                crate::data::database::CompactionStatus::Critical => "🟠 Critical",
                crate::data::database::CompactionStatus::Imminent => "🔴 Imminent",
            };
            text.push(Line::from(format!("  {}", status_text)));
            
            // Cost information
            text.push(Line::from(""));
            text.push(Line::from(Span::styled(
                "Cost Analysis:",
                Style::default().add_modifier(Modifier::BOLD),
            )));
            text.push(Line::from(format!("  Session Cost: ${:.4}", session.session_cost)));
            
            // Message information
            text.push(Line::from(""));
            text.push(Line::from(Span::styled(
                "Messages:",
                Style::default().add_modifier(Modifier::BOLD),
            )));
            text.push(Line::from(format!("  Total: {} exchanges", session.message_count)));
            if session.message_count > 0 {
                text.push(Line::from(format!(
                    "  Avg tokens/msg: {}",
                    session.token_usage.total_tokens / session.message_count as u64
                )));
            }
            
            let detail = Paragraph::new(text)
                .block(
                    Block::default()
                        .title("Session Details")
                        .borders(Borders::ALL),
                );
                
            frame.render_widget(detail, area);
        } else {
            let msg = Paragraph::new("No session selected")
                .block(
                    Block::default()
                        .title("Session Details")
                        .borders(Borders::ALL),
                )
                .alignment(Alignment::Center);
                
            frame.render_widget(msg, area);
        }
    }
    
    fn render_metrics_widget(&self, frame: &mut Frame, area: Rect) {
        let global_stats = self.state.global_stats.lock().unwrap();
        let burn_rate = self.state.burn_rate.lock().unwrap();
        let period_metrics = self.state.period_metrics.lock().unwrap();
        
        if let Some(ref stats) = *global_stats {
            let mut text = vec![];
            
            // Show cumulative totals (we can't determine time-based metrics without timestamps)
            if let Some(ref periods) = *period_metrics {
                text.push(Line::from(vec![
                    Span::styled("📊 Cumulative Total: ", Style::default().fg(Color::Cyan)),
                    Span::raw(format!("{} tokens (${:.2})", periods.month_tokens, periods.month_cost)),
                ]));
            }
            
            // Burn rate and cost rate
            text.push(Line::from(vec![
                Span::raw("🔥 Burn Rate: "),
                Span::styled(
                    format!("{:.1} tokens/min", burn_rate.tokens_per_minute),
                    Style::default().fg(Color::Red),
                ),
                Span::raw("  💲 Cost Rate: "),
                Span::styled(
                    format!("${:.4}/min", burn_rate.cost_per_minute),
                    Style::default().fg(Color::Green),
                ),
            ]));
            
            // Message quota
            let msg_pct = (stats.message_quota_used as f64 / stats.message_quota_limit as f64) * 100.0;
            let msg_pct = if msg_pct >= 100.0 { 100.0 } else if msg_pct > 99.9 { 99.9 } else { msg_pct };
            text.push(Line::from(Span::styled(
                format!(
                    "Message Quota (Month): {} / {} ({:.1}%)",
                    stats.message_quota_used,
                    stats.message_quota_limit,
                    msg_pct
                ),
                Style::default().fg(Color::Yellow),
            )));
            
            // Calculate overall context usage
            let active_sessions = self.state.all_sessions.lock().unwrap();
            let total_context: u64 = active_sessions.iter().map(|s| s.token_usage.context_tokens).sum();
            let _total_history: u64 = active_sessions.iter().map(|s| s.token_usage.history_tokens).sum();
            let context_percentage = if stats.total_tokens > 0 {
                (total_context as f64 / stats.total_tokens as f64) * 100.0
            } else {
                0.0
            };
            
            // System-wide metrics with context breakdown
            text.push(Line::from(""));
            text.push(Line::from(format!(
                "Total: {} sessions | {} tokens ({}% context, {}% conversation) | ${:.2}",
                stats.total_conversations,
                stats.total_tokens,
                context_percentage as i32,
                (100.0 - context_percentage) as i32,
                stats.total_cost_estimate
            )));
            
            // Warning/critical counts
            if stats.conversations_warning > 0 || stats.conversations_critical > 0 {
                text.push(Line::from(format!(
                    "⚠️  {} warning | {} critical",
                    stats.conversations_warning,
                    stats.conversations_critical
                )));
            }
            
            let metrics = Paragraph::new(text)
                .block(
                    Block::default()
                        .title("System Metrics")
                        .borders(Borders::ALL)
                        .border_style(Style::default().fg(Color::Blue)),
                );
                
            frame.render_widget(metrics, area);
        }
    }
    
    fn render_footer(&self, frame: &mut Frame, area: Rect) {
        // Split footer into two rows: stats and keybinds
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(1), // Stats line
                Constraint::Length(2), // Keybinds
            ])
            .split(area);

        // Render stats line at top of footer
        self.render_stats_line(frame, chunks[0]);
        
        // Render keybinds at bottom
        let view_mode = self.state.view_mode.lock().unwrap().clone();
        
        let keybinds = match view_mode {
            crate::app::state::ViewMode::GlobalOverview => vec![
                ("G", "Current Dir"),
                ("L", "List All"),
                ("S", "Sessions"),
                ("P", "Provider"),
                ("R", "Refresh"),
                ("Q", "Quit"),
            ],
            crate::app::state::ViewMode::CurrentDirectory => vec![
                ("G", "Global View"),
                ("L", "List All"),
                ("S", "Sessions"),
                ("P", "Provider"),
                ("R", "Refresh"),
                ("Q", "Quit"),
            ],
            crate::app::state::ViewMode::ConversationList => vec![
                ("G", "Global View"),
                ("C", "Current Dir"),
                ("S", "Sessions"),
                ("P", "Provider"),
                ("↑↓", "Navigate"),
                ("Q", "Quit"),
            ],
            crate::app::state::ViewMode::SessionList => vec![
                ("G", "Global"),
                ("C", "Current"),
                ("A", "Toggle Active"),
                ("P", "Provider"),
                ("↑↓", "Navigate"),
                ("Enter", "Details"),
                ("Q", "Quit"),
            ],
            crate::app::state::ViewMode::SessionDetail => vec![
                ("Esc", "Back"),
                ("G", "Global"),
                ("S", "Sessions"),
                ("P", "Provider"),
                ("Q", "Quit"),
            ],
        };

        let spans: Vec<Span> = keybinds
            .iter()
            .flat_map(|(key, desc)| {
                vec![
                    Span::styled(
                        format!("[{}]", key),
                        Style::default()
                            .fg(Color::Yellow)
                            .add_modifier(Modifier::BOLD),
                    ),
                    Span::raw(format!(" {} ", desc)),
                ]
            })
            .collect();

        let footer = Paragraph::new(Line::from(spans))
            .block(
                Block::default()
                    .borders(Borders::TOP | Borders::LEFT | Borders::RIGHT | Borders::BOTTOM)
                    .border_style(Style::default().fg(Color::DarkGray)),
            )
            .alignment(Alignment::Center);

        frame.render_widget(footer, chunks[1]);
    }
    
    fn render_stats_line(&self, frame: &mut Frame, area: Rect) {
        let global_stats = self.state.global_stats.lock().unwrap();
        
        let mut spans = vec![];
        
        if let Some(ref stats) = *global_stats {
            let avg_window = 175_000u64; // Average context window
            
            // Calculate percentages with cap at 99.9%
            let token_percentage = if stats.total_tokens > 0 && stats.total_conversations > 0 {
                let total_capacity = avg_window * stats.total_conversations as u64;
                let pct = (stats.total_tokens as f64 / total_capacity as f64) * 100.0;
                if pct >= 100.0 { 100.0 } else if pct > 99.9 { 99.9 } else { pct }
            } else {
                0.0
            };
            
            let message_percentage = if stats.message_quota_limit > 0 {
                let pct = (stats.message_quota_used as f64 / stats.message_quota_limit as f64) * 100.0;
                if pct >= 100.0 { 100.0 } else if pct > 99.9 { 99.9 } else { pct }
            } else {
                0.0
            };
            
            // Token usage
            spans.push(Span::raw("Tokens: "));
            let total_capacity = if stats.total_conversations > 0 {
                avg_window * stats.total_conversations as u64
            } else {
                avg_window
            };
            spans.push(Span::styled(
                format!("{}/{}", stats.total_tokens, total_capacity),
                Style::default().fg(Color::Cyan),
            ));
            spans.push(Span::raw(format!(" ({:.1}%) ", token_percentage)));
            
            spans.push(Span::raw(" • "));
            
            // Cost
            spans.push(Span::raw("Cost: "));
            spans.push(Span::styled(
                format!("${:.2}", stats.total_cost_estimate),
                Style::default().fg(Color::Green),
            ));
            
            spans.push(Span::raw(" • "));
            
            // Message quota
            spans.push(Span::raw("Messages: "));
            spans.push(Span::styled(
                format!("{}/{}", stats.message_quota_used, stats.message_quota_limit),
                Style::default().fg(
                    if message_percentage > 90.0 {
                        Color::Red
                    } else if message_percentage > 70.0 {
                        Color::Yellow
                    } else {
                        Color::Green
                    }
                ),
            ));
            spans.push(Span::raw(format!(" ({:.1}%) ", message_percentage)));
        } else {
            spans.push(Span::raw("Loading statistics..."));
        }
        
        let stats_line = Paragraph::new(Line::from(spans))
            .alignment(Alignment::Center)
            .style(Style::default().fg(Color::Gray));
        
        frame.render_widget(stats_line, area);
    }

    fn render_help_overlay(&self, _frame: &mut Frame, _area: Rect) {
        // Simplified help overlay - would be implemented with centered popup
    }

    fn get_usage_color(&self, percentage: f64) -> Color {
        // Use Claude-specific thresholds when in Claude mode
        let data_source = self.state.get_active_data_source();

        match data_source {
            crate::data::DataSourceType::ClaudeCode => {
                // For Claude, use configurable thresholds
                let warning_threshold = self.state.config.claude_warning_threshold * 100.0;
                match percentage {
                    p if p >= 95.0 => Color::Red,      // Critical at 95%
                    p if p >= warning_threshold => Color::Yellow,  // Warning at config threshold (default 80%)
                    _ => Color::Green,
                }
            },
            _ => {
                // For other data sources, use the standard thresholds
                match percentage {
                    p if p >= 90.0 => Color::Red,
                    p if p >= 70.0 => Color::Yellow,
                    _ => Color::Green,
                }
            }
        }
    }

    pub fn is_switching_provider(&self) -> bool {
        self.switching_provider
    }

    pub fn reset_switching_flag(&mut self) {
        self.switching_provider = false;
    }

    pub fn handle_key(&mut self, key: crossterm::event::KeyCode) -> bool {
        use crossterm::event::KeyCode;

        let mut view_mode = self.state.view_mode.lock().unwrap();
        
        match key {
            KeyCode::Char('g') | KeyCode::Char('G') => {
                // Go to global overview
                *view_mode = crate::app::state::ViewMode::GlobalOverview;
                true
            }
            KeyCode::Char('l') | KeyCode::Char('L') => {
                // Show conversation list
                *view_mode = crate::app::state::ViewMode::ConversationList;
                true
            }
            KeyCode::Char('c') | KeyCode::Char('C') => {
                // Show latest conversation view
                *view_mode = crate::app::state::ViewMode::CurrentDirectory;
                true
            }
            KeyCode::Char('s') | KeyCode::Char('S') => {
                // Show session list
                *view_mode = crate::app::state::ViewMode::SessionList;
                true
            }
            KeyCode::Char('a') | KeyCode::Char('A') => {
                // Toggle active filter in session list
                if matches!(*view_mode, crate::app::state::ViewMode::SessionList) {
                    let mut show_active = self.state.show_active_only.lock().unwrap();
                    *show_active = !*show_active;
                    // Reset selection and scroll when filter changes
                    *self.state.selected_conversation_index.lock().unwrap() = 0;
                    *self.state.scroll_offset.lock().unwrap() = 0;
                }
                true
            }
            KeyCode::Enter => {
                // Enter detail view from session list
                if matches!(*view_mode, crate::app::state::ViewMode::SessionList) {
                    let directory_groups = self.state.directory_groups.lock().unwrap();
                    let show_active_only = *self.state.show_active_only.lock().unwrap();
                    let selected_idx = *self.state.selected_conversation_index.lock().unwrap();
                    
                    // Build visible sessions list (same logic as render)
                    let mut visible_sessions = Vec::new();
                    for group in directory_groups.iter() {
                        if show_active_only && group.active_session_count == 0 {
                            continue;
                        }
                        for session in &group.sessions {
                            if show_active_only && !session.is_active {
                                continue;
                            }
                            visible_sessions.push(session.clone());
                        }
                    }
                    
                    if selected_idx < visible_sessions.len() {
                        let selected_session = visible_sessions[selected_idx].clone();
                        *self.state.selected_session.lock().unwrap() = Some(selected_session);
                        *view_mode = crate::app::state::ViewMode::SessionDetail;
                    }
                }
                true
            }
            KeyCode::Esc => {
                // Go back from detail view
                if matches!(*view_mode, crate::app::state::ViewMode::SessionDetail) {
                    *view_mode = crate::app::state::ViewMode::SessionList;
                }
                true
            }
            KeyCode::Up => {
                // Navigate up in list views
                if matches!(*view_mode, crate::app::state::ViewMode::ConversationList | crate::app::state::ViewMode::SessionList) {
                    let mut selected = self.state.selected_conversation_index.lock().unwrap();
                    if *selected > 0 {
                        *selected -= 1;
                    }
                }
                true
            }
            KeyCode::Down => {
                // Navigate down in list views
                if matches!(*view_mode, crate::app::state::ViewMode::ConversationList | crate::app::state::ViewMode::SessionList) {
                    let max_idx = match *view_mode {
                        crate::app::state::ViewMode::ConversationList => {
                            self.state.all_conversations.lock().unwrap().len()
                        }
                        crate::app::state::ViewMode::SessionList => {
                            // Count visible sessions based on filter
                            let directory_groups = self.state.directory_groups.lock().unwrap();
                            let show_active_only = *self.state.show_active_only.lock().unwrap();
                            let mut count = 0;
                            for group in directory_groups.iter() {
                                if show_active_only && group.active_session_count == 0 {
                                    continue;
                                }
                                for session in &group.sessions {
                                    if show_active_only && !session.is_active {
                                        continue;
                                    }
                                    count += 1;
                                }
                            }
                            count
                        }
                        _ => 0,
                    };
                    
                    let mut selected = self.state.selected_conversation_index.lock().unwrap();
                    if *selected < max_idx.saturating_sub(1) {
                        *selected += 1;
                    }
                }
                true
            }
            KeyCode::Char('p') | KeyCode::Char('P') => {
                // Toggle provider - mark that we want to switch
                self.switching_provider = true;
                // The actual switching would need to be handled at a higher level
                // since it requires restarting the collector
                true
            }
            KeyCode::Char('r') | KeyCode::Char('R') => {
                // Force refresh
                true
            }
            KeyCode::Char('?') => {
                self.show_help = !self.show_help;
                true
            }
            KeyCode::Char('q') | KeyCode::Char('Q') => false,
            _ => true,
        }
    }
}
