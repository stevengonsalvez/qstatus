# Enhanced Claude Code Display Implementation Plan

## Overview
Enhance the Claude Code display in both q-status-menubar and q-status-cli to show active session metrics separately from cumulative usage, add configurable token limits with warnings, and display actual costs from JSONL data instead of calculated values.

## Current State Analysis
Both apps currently show cumulative Claude usage but lack:
- Clear distinction between active session and total usage
- Token limit configuration and warnings
- Display of actual costs from JSONL (using calculated costs instead)
- Session-level token breakdown (cache hits, etc.)

## Desired End State
Users can see at a glance:
- Current active session usage with remaining tokens
- Configured token limits with visual warnings
- Actual costs from Claude's JSONL data
- Clear separation between active and historical data

### Key Discoveries:
- JSONL entries contain `costUSD` field with actual costs at `q-status-menubar/Sources/Core/ClaudeCodeDataSource.swift:38`
- Session blocks use 5-hour periods at `q-status-cli/src/utils/session_blocks.rs:206`
- Active session detection already exists at `q-status-cli/src/ui/dashboard.rs:494`
- ccusage doesn't have "plans" but uses token limits at `ccusage/src/cli.ts` (--token-limit flag)

## What We're NOT Doing
- Not implementing subscription/plan management (ccusage doesn't have this)
- Not changing the 5-hour session block logic
- Not removing calculated costs (keep as fallback when costUSD missing)
- Not implementing complex session compaction

## Implementation Approach
Add active session tracking with configurable token limits, prioritize JSONL costs over calculated, and enhance UI to clearly show active vs cumulative metrics.

## Phase 1: Active Session Detection and Display

### Overview
Identify the current active session and display its metrics separately from cumulative totals.

### Changes Required:

#### 1. Swift - Add Active Session Tracking
**File**: `q-status-menubar/Sources/Core/ClaudeCodeDataSource.swift`
**Changes**: Add method to get active session data

```swift
// Add new method around line 300
func fetchActiveSession() async throws -> ClaudeSession? {
    let sessions = try await loadSessions()
    let now = Date()
    let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)

    // Find most recent session that's still active
    return sessions.values
        .filter { $0.endTime > fiveHoursAgo }
        .max(by: { $0.endTime < $1.endTime })
}

// Add to UsageSnapshot for active session data
struct ActiveSessionData {
    let sessionId: String
    let startTime: Date
    let tokens: ClaudeTokenUsage
    let cost: Double  // From costUSD field
    let isActive: Bool
}
```

#### 2. Swift - Update UI for Active Session
**File**: `q-status-menubar/Sources/App/DropdownView.swift`
**Changes**: Add active session display section (around line 70)

```swift
// After burn rate, before sessions list
if let activeSession = viewModel.activeSession {
    VStack(alignment: .leading, spacing: 4) {
        Text("Active Session")
            .font(.caption)
            .foregroundStyle(.secondary)

        HStack {
            Label("\(activeSession.tokens.total.formatted())",
                  systemImage: "bolt.circle")
            Spacer()
            Text("$\(activeSession.cost, specifier: "%.4f")")
                .foregroundStyle(.green)
        }
        .font(.system(.body, design: .monospaced))
    }
    .padding(.horizontal)

    Divider()
}
```

#### 3. Rust - Add Active Session Tracking
**File**: `q-status-cli/src/data/claude_datasource.rs`
**Changes**: Add method to get active session (around line 400)

```rust
pub fn get_active_session(&self) -> Result<Option<ClaudeSession>> {
    let sessions = self.sessions.lock().unwrap();
    let now = Utc::now();
    let five_hours_ago = now - Duration::hours(5);

    Ok(sessions
        .values()
        .filter(|s| s.end_time > five_hours_ago)
        .max_by_key(|s| s.end_time)
        .cloned())
}
```

#### 4. Rust - Update Dashboard Display
**File**: `q-status-cli/src/ui/dashboard.rs`
**Changes**: Add active session widget (around line 200)

```rust
// Add new widget for active session
fn render_active_session(&self, f: &mut Frame, area: Rect) {
    if let Some(active) = &self.state.active_session {
        let text = vec![
            Line::from(vec![
                Span::raw("Active: "),
                Span::styled(
                    format!("{} tokens", active.total_tokens),
                    Style::default().fg(Color::Green)
                ),
                Span::raw(" | "),
                Span::styled(
                    format!("${:.4}", active.cost),
                    Style::default().fg(Color::Yellow)
                ),
            ]),
        ];

        let paragraph = Paragraph::new(text)
            .block(Block::default()
                .title("Active Session")
                .borders(Borders::ALL));

        f.render_widget(paragraph, area);
    }
}
```

### Success Criteria:

#### Automated Verification:
- [ ] Active session detection returns most recent session within 5 hours
- [ ] costUSD field is properly extracted from JSONL
- [ ] Tests pass for active session logic

#### Manual Verification:
- [ ] Active session shows separately from totals
- [ ] Active session updates when switching sessions
- [ ] Cost shows actual JSONL value, not calculated

---

## Phase 2: Token Limits and Warnings

### Overview
Add configurable token limits with visual warnings when approaching or exceeding limits.

### Changes Required:

#### 1. Swift - Add Token Limit Configuration
**File**: `q-status-menubar/Sources/Core/Settings.swift`
**Changes**: Add token limit settings (around line 50)

```swift
@AppStorage("claudeTokenLimit") public var claudeTokenLimit: Int = 500000
@AppStorage("claudeTokenWarningThreshold") public var claudeTokenWarningThreshold: Double = 0.8

// Add computed property for warning state
public var isApproachingTokenLimit: Bool {
    guard claudeTokenLimit > 0 else { return false }
    let usage = getCurrentClaudeUsage()
    return Double(usage) / Double(claudeTokenLimit) > claudeTokenWarningThreshold
}
```

#### 2. Swift - Add Visual Warnings
**File**: `q-status-menubar/Sources/App/DropdownView.swift`
**Changes**: Add warning indicators (around line 45)

```swift
// In the token display section
if settings.claudeTokenLimit > 0 {
    let usage = viewModel.totalTokens
    let limit = settings.claudeTokenLimit
    let percentage = Double(usage) / Double(limit)

    HStack {
        ProgressView(value: percentage)
            .tint(percentage > 0.8 ? .orange : .accentColor)

        Text("\(Int(percentage * 100))% of \(limit.formatted())")
            .font(.caption)
            .foregroundStyle(percentage > 0.8 ? .orange : .secondary)
    }

    if percentage > 0.8 {
        Label("Approaching token limit", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}
```

#### 3. Rust - Add Token Limit Configuration
**File**: `q-status-cli/src/app/config.rs`
**Changes**: Add configuration fields

```rust
#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    // ... existing fields

    #[serde(default = "default_claude_token_limit")]
    pub claude_token_limit: usize,

    #[serde(default = "default_claude_warning_threshold")]
    pub claude_warning_threshold: f64,
}

fn default_claude_token_limit() -> usize {
    500000  // 500k tokens default
}

fn default_claude_warning_threshold() -> f64 {
    0.8  // Warn at 80%
}
```

#### 4. Rust - Add Warning Display
**File**: `q-status-cli/src/ui/dashboard.rs`
**Changes**: Update gauge display with warnings (around line 140)

```rust
// In render_token_usage method
let warning_style = if percentage > 80.0 {
    Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
} else if percentage > 95.0 {
    Style::default().fg(Color::Red).add_modifier(Modifier::BOLD)
} else {
    Style::default().fg(Color::Green)
};

// Add warning text if approaching limit
if percentage > 80.0 {
    let warning = if percentage > 95.0 {
        "⚠️  EXCEEDING TOKEN LIMIT"
    } else {
        "⚠️  Approaching token limit"
    };

    spans.push(Span::styled(warning, warning_style));
}
```

### Success Criteria:

#### Automated Verification:
- [ ] Token limits are configurable via settings
- [ ] Warning thresholds trigger at correct percentages
- [ ] Configuration persists across restarts

#### Manual Verification:
- [ ] Visual warnings appear at 80% usage
- [ ] Colors change appropriately (green/orange/red)
- [ ] Limits can be configured in preferences/config

---

## Phase 3: Cost Display Enhancement

### Overview
Prioritize actual costs from JSONL over calculated values and show cost breakdowns.

### Changes Required:

#### 1. Swift - Use JSONL Cost Priority
**File**: `q-status-menubar/Sources/Core/ClaudeCodeDataSource.swift`
**Changes**: Modify cost handling (around line 460)

```swift
// Update cost calculation to prefer JSONL cost
private func getEntryCoast(entry: ClaudeUsageEntry) -> Double {
    // Prefer JSONL-provided cost
    if let cost = entry.costUSD {
        return cost
    }

    // Fallback to calculated cost
    guard let model = entry.message.model else { return 0.0 }
    return calculator.calculateCost(
        tokens: entry.message.usage,
        model: model,
        mode: .calculate  // Force calculation when no JSONL cost
    )
}

// Add tracking of cost source
struct CostBreakdown {
    let total: Double
    let fromJSONL: Double  // Actual costs
    let calculated: Double  // Calculated costs
    let percentActual: Double  // % from JSONL
}
```

#### 2. Rust - Use JSONL Cost Priority
**File**: `q-status-cli/src/data/claude_datasource.rs`
**Changes**: Update cost handling (around line 220)

```rust
// Track cost sources
#[derive(Debug, Clone)]
pub struct CostBreakdown {
    pub total: f64,
    pub from_jsonl: f64,
    pub calculated: f64,
    pub percent_actual: f64,
}

// Update cost calculation
fn get_entry_cost(&self, entry: &ClaudeUsageEntry) -> (f64, bool) {
    if let Some(cost) = entry.cost_usd {
        (cost, true)  // From JSONL
    } else {
        let calculated = self.cost_calculator.calculate_cost(
            &entry.message.usage,
            &entry.message.model.as_deref().unwrap_or("claude-3-5-sonnet"),
            CostMode::Calculate,
        );
        (calculated, false)  // Calculated
    }
}
```

#### 3. Display Cost Source
**File**: `q-status-menubar/Sources/App/DropdownView.swift`
**Changes**: Show cost source indicator

```swift
// Add indicator for cost source
HStack {
    Text("$\(cost, specifier: "%.4f")")

    if costBreakdown.percentActual < 100 {
        Image(systemName: "questionmark.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("Some costs are estimated")
    }
}
```

### Success Criteria:

#### Automated Verification:
- [ ] costUSD from JSONL is prioritized over calculated
- [ ] Cost breakdown tracks sources correctly
- [ ] Fallback calculation works when costUSD missing

#### Manual Verification:
- [ ] Actual costs display when available
- [ ] Indicator shows when costs are estimated
- [ ] Total costs remain accurate

---

## Phase 4: UI Improvements

### Overview
Enhance visual distinction between active and cumulative data with better layout.

### Changes Required:

#### 1. Swift - Reorganize Layout
**File**: `q-status-menubar/Sources/App/DropdownView.swift`
**Changes**: Create clear sections

```swift
// New layout structure
VStack {
    // Header with provider
    HeaderSection()

    // Active Session Section
    if hasActiveSession {
        ActiveSessionSection()
        Divider()
    }

    // Cumulative Stats Section
    CumulativeStatsSection()
    Divider()

    // Token Limits Section
    if hasTokenLimits {
        TokenLimitsSection()
        Divider()
    }

    // Sessions List
    SessionsListSection()

    // Footer Actions
    FooterActionsSection()
}
```

#### 2. Rust - Improve Layout
**File**: `q-status-cli/src/ui/dashboard.rs`
**Changes**: Add dedicated active session area

```rust
// Split layout for active vs cumulative
let chunks = Layout::default()
    .direction(Direction::Vertical)
    .constraints([
        Constraint::Length(3),   // Header
        Constraint::Length(6),   // Active session
        Constraint::Length(8),   // Token usage
        Constraint::Min(10),     // Sessions list
        Constraint::Length(3),   // Footer
    ])
    .split(area);

// Render active session prominently
self.render_active_session(f, chunks[1]);
```

### Success Criteria:

#### Automated Verification:
- [ ] Layout renders without overlap
- [ ] All sections display correctly

#### Manual Verification:
- [ ] Active session clearly distinguished
- [ ] Token limits visible when configured
- [ ] Cost sources indicated
- [ ] Improved visual hierarchy

---

## Testing Strategy

### Unit Tests:
- Active session detection with various timestamps
- Token limit warning calculations
- Cost source prioritization
- JSONL cost extraction

### Integration Tests:
- Full UI rendering with active sessions
- Settings persistence for token limits
- Cost calculation fallback scenarios

### Manual Testing Steps:
1. Start a new Claude Code session
2. Verify active session appears immediately
3. Configure token limits in settings
4. Verify warnings appear at thresholds
5. Check cost display shows actual values
6. Switch between providers, verify Claude-specific features
7. Test with missing costUSD fields

## Performance Considerations
- Cache active session calculation (update every minute)
- Avoid recalculating cost breakdowns on every render
- Efficient JSONL parsing for cost extraction

## Migration Notes
- Existing calculated costs remain as fallback
- Token limits default to 500k if not configured
- No data migration required

## References
- Current implementation: `q-status-menubar/Sources/Core/ClaudeCodeDataSource.swift`
- Session blocks: `q-status-cli/src/utils/session_blocks.rs`
- ccusage patterns: `ccusage/src/cli.ts`
- Cost calculation: `q-status-menubar/Sources/Core/ClaudeCostCalculator.swift`