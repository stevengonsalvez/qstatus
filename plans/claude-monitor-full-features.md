# Claude Code Usage Monitor Full Features Implementation Plan

## Overview
Integrate all Claude-Code-Usage-Monitor features into q-status-menubar when Claude Code is selected as the data source.

## Current State
- ✅ SessionBlockCalculator fully implemented but not integrated in UI
- ✅ BurnRateCalculator exists but unused
- ✅ Basic plan support (Free/Pro/Team)
- ✅ Cost calculation with cache token support
- ❌ Missing plan selection UI
- ❌ Missing three-bar display (cost/tokens/messages)
- ❌ Missing burn rate display
- ❌ Missing time remaining in billing block

## Implementation Phases

### Phase 1: Plan System Enhancement
1. **Update ClaudePlan enum** (Settings.swift)
   - Add Max5 and Max20 plans
   - Add Custom plan with P90 calculation support
   - Define three limits per plan: tokens, cost, messages

2. **Plan Selection UI** (PreferencesWindow.swift)
   - Add plan picker when Claude is selected
   - Show plan details (limits and pricing)
   - Persist selected plan in settings

### Phase 2: Three-Bar Progress Display
1. **Update DropdownView**
   - Replace single progress bar with three bars
   - Cost progress (% of plan's cost limit)
   - Token progress (% of plan's token limit)
   - Message progress (% of plan's message limit)
   - Color coding: green→yellow→red based on usage

2. **Progress Calculations** (ClaudeCodeDataSource.swift)
   - Calculate percentages for each limit type
   - Support Custom plan's P90 calculations

### Phase 3: Billing Block Integration
1. **Wire SessionBlockCalculator** (DropdownView.swift)
   - Display current block period (e.g., "Block 2 of 5")
   - Show time remaining in current block
   - Display block start/end times

2. **Block Progress Bar**
   - Visual indicator of time elapsed in current 5-hour block
   - Separate from usage progress bars

### Phase 4: Burn Rate & Predictions
1. **Burn Rate Display** (DropdownView.swift)
   - Tokens/minute rate
   - Cost/hour rate
   - Messages/hour rate

2. **Predictions**
   - Time until token limit
   - Time until cost limit
   - Time until message limit
   - Highlight the limiting factor

### Phase 5: Enhanced UI Features
1. **Compact/Expanded Views**
   - Compact: Show only critical limiting factor
   - Expanded: Show all three bars + burn rates

2. **Alert System**
   - Warning at 80% of any limit
   - Critical at 95% of any limit
   - Block transition notifications

## File Changes Required

### Settings.swift
- Expand ClaudePlan enum with all plans
- Add plan limit constants
- Add P90 calculation settings for Custom plan

### DropdownView.swift
- Replace single progress with three-bar system
- Integrate SessionBlockCalculator display
- Add burn rate section
- Add predictions section

### ClaudeCodeDataSource.swift
- Add message counting
- Calculate all three progress percentages
- Support Custom plan P90 logic

### PreferencesWindow.swift
- Add plan selection dropdown
- Show plan details and limits
- Add Custom plan configuration

### SessionBlockCalculator.swift
- Already implemented, just needs UI integration

## Data Model Updates

### ClaudeSession
- Add messageCount property
- Add burnRates property
- Add predictions property

### ClaudePlan
```swift
enum ClaudePlan {
    case free
    case pro      // 19K tokens, $18, 1000 messages
    case max5     // 88K tokens, $35, 5000 messages
    case max20    // 220K tokens, $140, 20000 messages
    case custom   // P90-based limits

    var tokenLimit: Int
    var costLimit: Double
    var messageLimit: Int
}
```

## UI Mockup

```
Claude Code - main.py [2h 15m remaining in block]

📊 Usage (Pro Plan - $18/month)
Tokens:  ████████░░ 75% (14.2K/19K) | 2.3K/hr
Cost:    ██████░░░░ 62% ($11.16/$18) | $1.80/hr
Messages: ███░░░░░░░ 28% (280/1000) | 45/hr

⚠️ Token limit in ~2.5 hours at current rate

🔥 Current Block (2/5 today)
████████████░░░░░░░░ 60% | 2h 15m left
```

## Testing Requirements
- Test each plan's limit calculations
- Test P90 calculation for Custom plan
- Test burn rate calculations
- Test prediction accuracy
- Test UI updates with live data

## Success Metrics
- All three progress bars update in real-time
- Burn rates calculated accurately
- Predictions help users manage usage
- Plan switching works seamlessly
- 5-hour blocks display correctly