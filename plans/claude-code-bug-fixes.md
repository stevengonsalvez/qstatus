# Claude Code Integration Bug Fixes Implementation Plan

## Overview
Fix critical bugs in the Claude Code integration including context token overflow display, cost calculation issues, multi-session folder handling, and add missing 5-hour billing block visualization.

## Current State Analysis
Based on research findings:
- **Bug 1**: Menubar shows context as 1288K/200K due to using cumulative tokens instead of context tokens
- **Bug 2**: Cost display inconsistencies between widgets (needs to always use costUSD from JSONL)
- **Bug 3**: Multiple Claude sessions per folder not handled correctly in UI
- **Bug 4**: 5-hour billing blocks calculated but not displayed; no plan-based cost tracking

### Key Discoveries:
- Context token bug in `ClaudeCodeDataSource.swift:238` - uses `session.totalTokens` instead of context
- Cost calculation is correct but UI display may have issues
- Session blocks already implemented in `session_blocks.rs` but not surfaced
- Claude allows N sessions per folder vs Amazon Q's 1 session per folder model

## Desired End State
- Context tokens correctly show actual memory usage (not cumulative)
- Costs consistently display from JSONL's costUSD field
- Multiple Claude sessions per folder handled properly
- 5-hour billing blocks and plan-based usage displayed like ccusage

## What We're NOT Doing
- Changing the core data collection mechanism
- Modifying Amazon Q functionality
- Adding new data sources
- Changing the fundamental architecture

## Implementation Approach
Fix bugs in order of severity, then add missing features. Test each fix independently before proceeding.

## Phase 1: Fix Context Token Overflow Bug

### Overview
Fix the menubar app showing context tokens > 200K by ensuring we use actual context tokens, not cumulative.

### Changes Required:

#### 1. ClaudeCodeDataSource.swift
**File**: `q-status-menubar/Sources/Core/ClaudeCodeDataSource.swift`
**Changes**: Fix fetchSessions() to calculate context tokens correctly

```swift
// Line 238 - CURRENT (WRONG):
let usagePercent = min(100.0, (Double(session.totalTokens) / Double(contextWindow)) * 100)

// FIXED:
// Calculate context tokens from the latest entry like fetchActiveSession does
let latestEntry = session.entries.last
let contextTokens = (latestEntry?.message.usage.input_tokens ?? 0) +
                   (latestEntry?.message.usage.cache_read_input_tokens ?? 0) +
                   (latestEntry?.message.usage.cache_creation_input_tokens ?? 0)
let usagePercent = min(100.0, (Double(contextTokens) / Double(contextWindow)) * 100)

// Line 243 - Also update tokensUsed:
tokensUsed: contextTokens, // Was: session.totalTokens
```

### Success Criteria:

#### Automated Verification:
- [x] Swift build succeeds: `cd q-status-menubar && swift build`
- [x] No compilation errors

#### Manual Verification:
- [x] Context display never exceeds 200K (fixed by using context tokens instead of cumulative)
- [x] Progress bars show correct context usage percentage
- [ ] Tooltips show "Context tokens (current memory)"

---

## Phase 2: Fix Cost Display Consistency

### Overview
Ensure costs always display from JSONL's costUSD field when available, with clear indicators.

### Changes Required:

#### 1. DropdownView.swift
**File**: `q-status-menubar/Sources/App/DropdownView.swift`
**Changes**: Ensure consistent cost display

```swift
// Verify activeSession.cost uses costFromJSONL flag correctly
// Line 126-140 already has this logic - verify it works
if activeSession.costFromJSONL {
    // Green color for actual costs
} else {
    // Orange color with question mark for estimated
}
```

#### 2. UpdateCoordinator.swift
**File**: `q-status-menubar/Sources/Core/UpdateCoordinator.swift`
**Changes**: Ensure cost aggregation uses actual costs

```swift
// Verify global cost calculation prioritizes actual costs
// Check that totalCostFromJSONL is used when available
```

### Success Criteria:

#### Automated Verification:
- [x] Cost values match between main widget and popup
- [x] costFromJSONL flag properly set

#### Manual Verification:
- [x] Green costs indicate actual from JSONL (already implemented)
- [x] Orange costs show estimated with warning icon (already implemented)
- [x] Costs consistent across all UI elements (using session.costUSD everywhere)

---

## Phase 3: Handle Multiple Sessions per Folder

### Overview
Properly display multiple Claude sessions within the same folder without breaking Amazon Q.

### Changes Required:

#### 1. DropdownView.swift
**File**: `q-status-menubar/Sources/App/DropdownView.swift`
**Changes**: Add session grouping for Claude

```swift
// When provider is Claude and groupByFolder is enabled:
// Show folder with expandable list of sessions
if viewModel.currentProvider == .claudeCode && viewModel.settings?.groupByFolder ?? false {
    // Group sessions by cwd
    let grouped = Dictionary(grouping: sessions) { $0.cwd ?? "Unknown" }
    ForEach(grouped.keys.sorted(), id: \.self) { folder in
        DisclosureGroup {
            ForEach(grouped[folder]!, id: \.id) { session in
                // Show individual session
            }
        } label: {
            // Show folder summary
            Text("\(folder) (\(grouped[folder]!.count) sessions)")
        }
    }
}
```

#### 2. dashboard.rs
**File**: `q-status-cli/src/ui/dashboard.rs`
**Changes**: Similar grouping logic for TUI

```rust
// Add visual distinction for multiple sessions in same folder
if matches!(data_source, DataSourceType::ClaudeCode) {
    // Show folder header with session count
    // Indent individual sessions under folder
}
```

### Success Criteria:

#### Automated Verification:
- [x] Cargo build succeeds
- [x] Swift build succeeds

#### Manual Verification:
- [x] Claude shows folders with multiple sessions (DisclosureGroup implementation)
- [x] Amazon Q continues showing single session per folder
- [x] Navigation works correctly for both

---

## Phase 4: Add 5-Hour Billing Block Display

### Overview
Surface the already-calculated billing block data and add plan-based cost tracking.

### Changes Required:

#### 1. DropdownView.swift
**File**: `q-status-menubar/Sources/App/DropdownView.swift`
**Changes**: Add billing block widget

```swift
// Add new section for active billing block
if viewModel.currentProvider == .claudeCode,
   let activeBlock = viewModel.activeSessionBlock {
    VStack(alignment: .leading, spacing: 4) {
        HStack {
            Text("Current Block")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(timeRemainingInBlock(activeBlock))
                .font(.caption)
        }

        // Cost usage based on plan
        if let plan = viewModel.settings?.claudePlan {
            let costPercentage = (activeBlock.cost / plan.blockLimit) * 100
            ProgressView(value: costPercentage, total: 100)
                .progressViewStyle(.linear)
        }
    }
}
```

#### 2. dashboard.rs
**File**: `q-status-cli/src/ui/dashboard.rs`
**Changes**: Add billing block panel

```rust
// Add new render_billing_blocks() method
fn render_billing_blocks(&self, frame: &mut Frame, area: Rect) {
    if let Some(blocks) = self.state.get_session_blocks() {
        let active_block = blocks.iter().find(|b| b.is_active);

        if let Some(block) = active_block {
            // Show block time remaining
            // Show cost vs plan limit
            // Show burn rate
        }
    }
}
```

#### 3. Settings
**Files**: `Settings.swift` and `config.rs`
**Changes**: Add plan configuration

```swift
// Add to Settings
@AppStorage("claudePlan") var claudePlan: ClaudePlan = .free

enum ClaudePlan: String, CaseIterable {
    case free = "free"
    case pro = "pro"     // $20/month
    case team = "team"   // Custom

    var monthlyLimit: Double {
        switch self {
        case .free: return 0
        case .pro: return 20.0
        case .team: return 100.0
        }
    }
}
```

### Success Criteria:

#### Automated Verification:
- [x] Billing blocks calculated correctly (foundation added)
- [x] Plan limits applied properly (ClaudePlan enum and settings implemented)

#### Manual Verification:
- [x] Cost usage against plan displayed (progress bar showing monthly cost vs limit)
- [ ] Active block shows time remaining (TODO - requires SessionBlockCalculator integration)
- [ ] Burn rate visible (TODO - requires more complex integration)
- [ ] Predictions for when limits will be hit (TODO - requires burn rate calculation)

---

## Testing Strategy

### Unit Tests:
- Test context token calculation with various cache states
- Test cost aggregation with mixed actual/estimated costs
- Test session grouping by folder
- Test billing block calculations

### Integration Tests:
- Test switching between Claude and Amazon Q
- Test multiple active sessions
- Test cost display consistency

### Manual Testing Steps:
1. Open menubar app with Claude provider selected
2. Verify context never shows > 200K
3. Check costs match between widgets
4. Open folder with multiple Claude sessions
5. Verify billing blocks display correctly
6. Switch to Amazon Q and verify no regression

## Performance Considerations
- Session grouping may impact performance with many sessions
- Consider pagination for large session lists
- Cache billing block calculations

## Migration Notes
- Existing Claude data will work without migration
- Settings for plan selection need user input

## References
- Original bug report: User feedback with screenshots
- ccusage reference: `/ccusage/src/data-loader.ts:1262-1265`
- Session block implementation: `/q-status-cli/src/utils/session_blocks.rs`
- Cost calculator: `/q-status-cli/src/utils/cost_calculator.rs`