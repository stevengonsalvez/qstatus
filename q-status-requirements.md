# Q-Status Requirements - Dual Approach

## Executive Summary

After discovering that PTY wrappers are fundamentally incompatible with Q's terminal REPL, we're pivoting to two independent monitoring solutions that observe Q's behavior without interfering with its operation.

## Problem Statement

Amazon Q CLI (q) consumes tokens during usage but provides no real-time visibility into:
- Current token usage within a session
- Approaching token limits
- Cost accumulation
- Usage patterns and trends

Users need visibility without interference with Q's terminal operations.

## Solution Architecture

Two independent, non-invasive monitoring approaches:

### Approach A: macOS Menu Bar Application

A native macOS menu bar application that monitors Q's SQLite database and displays real-time metrics.

### Approach B: Independent CLI Monitor

A standalone terminal dashboard application (similar to Claude Code Usage Monitor) that runs in a separate terminal window/pane.

---

## Approach A: macOS Menu Bar Application

### Overview
Native macOS application residing in the system menu bar, providing ambient awareness of Q token usage.

### Technical Requirements

#### Core Functionality
1. **Database Monitoring**
   - Monitor Q's SQLite database at: `~/.aws/q/db/q.db`
   - Poll interval: 2-5 seconds (configurable)
   - Track conversations, messages, and token usage

2. **Menu Bar Display**
   - Compact display showing current usage percentage
   - Color coding: Green (0-70%), Yellow (70-90%), Red (90-100%)
   - Click for detailed dropdown view
   - Optional notification badges

3. **Dropdown Details**
   - Current session tokens used
   - Tokens remaining
   - Estimated cost
   - Time until limit
   - Usage rate (tokens/minute)
   - Historical usage graph

4. **Notifications**
   - macOS native notifications at thresholds (70%, 90%, 95%)
   - Sound alerts (optional)
   - Notification Center integration

### Technical Stack Options

#### Option 1: Swift/SwiftUI (Native)
- **Pros**: Native performance, full macOS integration, efficient
- **Cons**: Platform-specific, requires Xcode
- **Libraries**: SQLite.swift, Charts

#### Option 2: Python with rumps/pystray
- **Pros**: Cross-platform potential, easier development
- **Cons**: Requires Python runtime, larger footprint
- **Libraries**: rumps, sqlite3, matplotlib

#### Option 3: Electron
- **Pros**: Web technologies, rich UI possibilities
- **Cons**: Heavy resource usage, not ideal for menu bar
- **Libraries**: electron, sqlite3, chart.js

### User Interface Requirements

1. **Menu Bar Icon**
   - Monochrome icon matching macOS style
   - Optional badge with percentage
   - Animation during active sessions

2. **Dropdown Menu**
   - Clean, native macOS styling
   - Real-time updates without flicker
   - Keyboard shortcuts support

3. **Preferences Window**
   - Update interval configuration
   - Notification thresholds
   - Color scheme selection
   - Auto-start at login

### Performance Requirements
- Memory usage: < 50MB
- CPU usage: < 1% when idle, < 5% during updates
- Battery efficient for laptop users
- No spinning beach balls

---

## Approach B: Independent CLI Monitor

### Overview
Standalone terminal application providing rich, real-time dashboard for Q token usage, inspired by Claude Code Usage Monitor.

### Technical Requirements

#### Core Functionality
1. **Database Monitoring**
   - Direct SQLite connection to Q's database
   - Real-time change detection via polling or file watching
   - Historical data retention (last 7 days)

2. **Terminal UI Components**
   - Progress bars for token usage
   - Tables for session history
   - Live graphs for usage trends
   - Cost calculator display
   - Rate limiting warnings

3. **Data Analytics**
   - Usage patterns analysis
   - Predictive burn rate calculations
   - Session limit predictions
   - Cost projections

4. **Multi-Session Support**
   - Track multiple Q sessions simultaneously
   - Aggregate statistics across sessions
   - Per-session and global views

### Technical Stack

#### Primary: Python with Rich/Textual
- **Framework**: Textual for TUI or Rich for simpler display
- **Database**: sqlite3 for database access
- **Analytics**: pandas for data processing
- **Plotting**: plotext for terminal graphs

#### Alternative: Rust with Ratatui
- **Framework**: Ratatui for TUI
- **Database**: rusqlite
- **Async**: tokio for event handling
- **Performance**: Superior performance and efficiency

### User Interface Requirements

1. **Dashboard Layout**
   ```
   ┌─────────────────────────────────────────────┐
   │ Q Token Monitor v1.0.0  [Connected]        │
   ├─────────────────────────────────────────────┤
   │ Current Session                             │
   │ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 75%     │
   │ Tokens: 33,000 / 44,000                    │
   │ Rate: 250 tokens/min                       │
   │ Est. Time Remaining: 44 minutes            │
   ├─────────────────────────────────────────────┤
   │ Cost Analysis                               │
   │ Session: $0.42 | Today: $2.31 | Month: $48 │
   ├─────────────────────────────────────────────┤
   │ Usage Graph (Last Hour)                    │
   │ ▁▂▃▄▅▆▇█▇▆▅▄▃▂▁                           │
   ├─────────────────────────────────────────────┤
   │ [R]efresh [S]ettings [H]istory [Q]uit      │
   └─────────────────────────────────────────────┘
   ```

2. **Color Coding**
   - Green: Safe usage (0-70%)
   - Yellow: Warning zone (70-90%)
   - Red: Critical (90-100%)
   - Blue: Informational elements
   - White: Standard text

3. **Interactive Features**
   - Keyboard navigation
   - Refresh on demand
   - Export data to CSV
   - Clear history option

### Performance Requirements
- Refresh rate: 0.5-10 Hz (configurable)
- Smooth animations without flicker
- Responsive to terminal resize
- Low CPU usage (< 5% during updates)

---

## Shared Requirements

### Database Schema Understanding
Both approaches need to understand Q's SQLite schema:
- Conversations table
- Messages table  
- Token tracking columns
- Timestamp formats
- Session identification

### Configuration
- YAML/TOML configuration file
- Environment variable overrides
- Sensible defaults
- Per-user settings in `~/.config/q-status/`

### Error Handling
- Graceful handling of database locks
- Q not running scenarios
- Database schema changes
- Network issues (for remote features)

### Security
- Read-only database access
- No storage of message content
- Optional encryption for config
- Secure credential handling if needed

### Distribution
- **Menu Bar**: DMG installer, Homebrew cask
- **CLI Monitor**: pip/pipx, Homebrew formula, cargo install

---

## Development Approach

### Phase 1: Prototype
- Basic database reading
- Simple UI implementation
- Core metrics calculation

### Phase 2: MVP
- Full UI implementation
- Real-time updates
- Basic configuration

### Phase 3: Enhancement
- Advanced analytics
- Historical tracking
- Export capabilities

### Phase 4: Polish
- Performance optimization
- Comprehensive testing
- Documentation

---

## Success Criteria

1. **Non-Invasive**: Zero interference with Q's operation
2. **Accurate**: Real-time, accurate token counts
3. **Performant**: Minimal resource usage
4. **Reliable**: Stable, crash-free operation
5. **User-Friendly**: Intuitive, beautiful interface
6. **Maintainable**: Clean, documented code

---

## Repository Structure

```
q-status-menubar/
├── src/
├── tests/
├── docs/
├── README.md
└── ...

q-status-cli/
├── src/
├── tests/
├── docs/  
├── README.md
└── ...
```

Each approach will be developed independently in separate git worktrees, allowing parallel development and separate Claude sessions for focused implementation.