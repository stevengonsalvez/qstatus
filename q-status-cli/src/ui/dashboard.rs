// ABOUTME: Main dashboard layout and rendering logic
// Implements the primary UI following Ratatui best practices

use crate::app::state::AppState;
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Gauge, Paragraph},
    Frame,
};
use std::sync::Arc;

pub struct Dashboard {
    state: Arc<AppState>,
    show_help: bool,
}

impl Dashboard {
    pub fn new(state: Arc<AppState>) -> Self {
        Self {
            state,
            show_help: false,
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
        let status = if is_connected {
            "Connected"
        } else {
            "Disconnected"
        };
        let status_color = if is_connected {
            Color::Green
        } else {
            Color::Red
        };

        let header_text = vec![
            Span::styled(
                "Q-Status Monitor",
                Style::default().add_modifier(Modifier::BOLD),
            ),
            Span::raw(" v0.1.0  ["),
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
                // Original layout for current directory view
                let chunks = Layout::default()
                    .direction(Direction::Vertical)
                    .constraints([
                        Constraint::Length(6),  // Token usage gauge
                        Constraint::Length(4),  // Cost analysis
                        Constraint::Min(10),    // Session details (expanded)
                    ])
                    .split(area);

                self.render_token_gauge(frame, chunks[0]);
                self.render_cost_panel(frame, chunks[1]);
                self.render_usage_info(frame, chunks[2]);
            }
            crate::app::state::ViewMode::ConversationList => {
                self.render_conversation_list(frame, area);
            }
        }
    }

    fn render_token_gauge(&self, frame: &mut Frame, area: Rect) {
        let usage = self.state.token_usage.lock().unwrap();
        let percentage = usage.percentage.min(100.0);
        let color = self.get_usage_color(percentage);
        
        // Get compaction status indicator
        let status_indicator = match usage.compaction_status {
            crate::data::database::CompactionStatus::Safe => "🟢",
            crate::data::database::CompactionStatus::Warning => "🟡",
            crate::data::database::CompactionStatus::Critical => "🟠",
            crate::data::database::CompactionStatus::Imminent => "🔴",
        };

        let title = format!(
            "Token Usage - 175K Effective Limit {}",
            status_indicator
        );

        let label = format!(
            "{} / {} tokens ({:.1}%)",
            usage.used, usage.context_window, percentage
        );

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
            "Token Breakdown:",
            Style::default().add_modifier(Modifier::BOLD),
        )));
        text.push(Line::from(format!(
            "  Conversation: {} tokens",
            usage.history_tokens
        )));
        text.push(Line::from(format!(
            "  Context Files: {} tokens",
            usage.context_tokens
        )));
        text.push(Line::from(format!(
            "  Total: {} / {} ({:.1}%)",
            usage.used, usage.context_window, usage.percentage
        )));
        
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
    
    fn render_footer(&self, frame: &mut Frame, area: Rect) {
        let view_mode = self.state.view_mode.lock().unwrap().clone();
        
        let keybinds = match view_mode {
            crate::app::state::ViewMode::GlobalOverview => vec![
                ("G", "Current Dir"),
                ("L", "List All"),
                ("R", "Refresh"),
                ("Q", "Quit"),
            ],
            crate::app::state::ViewMode::CurrentDirectory => vec![
                ("G", "Global View"),
                ("L", "List All"),
                ("R", "Refresh"),
                ("Q", "Quit"),
            ],
            crate::app::state::ViewMode::ConversationList => vec![
                ("G", "Global View"),
                ("C", "Current Dir"),
                ("↑↓", "Navigate"),
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
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::DarkGray)),
            )
            .alignment(Alignment::Center);

        frame.render_widget(footer, area);
    }

    fn render_help_overlay(&self, _frame: &mut Frame, _area: Rect) {
        // Simplified help overlay - would be implemented with centered popup
    }

    fn get_usage_color(&self, percentage: f64) -> Color {
        match percentage {
            p if p >= 90.0 => Color::Red,
            p if p >= 70.0 => Color::Yellow,
            _ => Color::Green,
        }
    }

    pub fn handle_key(&mut self, key: crossterm::event::KeyCode) -> bool {
        use crossterm::event::KeyCode;

        let mut view_mode = self.state.view_mode.lock().unwrap();
        
        match key {
            KeyCode::Char('g') | KeyCode::Char('G') => {
                // Toggle between global and current directory view
                *view_mode = match *view_mode {
                    crate::app::state::ViewMode::GlobalOverview => crate::app::state::ViewMode::CurrentDirectory,
                    crate::app::state::ViewMode::CurrentDirectory => crate::app::state::ViewMode::GlobalOverview,
                    crate::app::state::ViewMode::ConversationList => crate::app::state::ViewMode::GlobalOverview,
                };
                true
            }
            KeyCode::Char('l') | KeyCode::Char('L') => {
                // Show conversation list
                *view_mode = crate::app::state::ViewMode::ConversationList;
                true
            }
            KeyCode::Char('c') | KeyCode::Char('C') => {
                // Show current directory view
                *view_mode = crate::app::state::ViewMode::CurrentDirectory;
                true
            }
            KeyCode::Up => {
                // Navigate up in list view
                if matches!(*view_mode, crate::app::state::ViewMode::ConversationList) {
                    let mut selected = self.state.selected_conversation_index.lock().unwrap();
                    if *selected > 0 {
                        *selected -= 1;
                    }
                }
                true
            }
            KeyCode::Down => {
                // Navigate down in list view
                if matches!(*view_mode, crate::app::state::ViewMode::ConversationList) {
                    let conversations = self.state.all_conversations.lock().unwrap();
                    let mut selected = self.state.selected_conversation_index.lock().unwrap();
                    if *selected < conversations.len().saturating_sub(1) {
                        *selected += 1;
                    }
                }
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
