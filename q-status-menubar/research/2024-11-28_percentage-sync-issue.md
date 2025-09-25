# Research: Status Bar vs Dropdown Percentage Discrepancy

## Date: 2024-11-28
## Issue: Status bar shows 22% while dropdown shows 54%

## Summary
The Mac status bar and dropdown are displaying different percentages because they calculate fundamentally different metrics. The user wants both to show the same value - specifically the dropdown's "Overall" percentage.

## Current Behavior

### Status Bar (Currently 22%)
- **Location**: MenuBarController.swift lines 53-60
- **Calculation**: Uses `PercentageCalculator.calculateCriticalPercentage()`
- **What it measures**: Critical percentage - MAX of:
  - Token usage vs personal maximum from previous blocks
  - Cost usage vs $140 baseline
- **Purpose**: Track billing/limit usage for current 5-hour block
- **Data source**:
  - `vm.activeClaudeSession`
  - `vm.maxTokensFromPreviousBlocks`
  - Monthly cost data if no active session

### Dropdown "Overall" (Currently 54%)
- **Location**: DropdownView.swift lines 1081-1103
- **Calculation**: `calculateSessionBlockPercentage()`
- **What it measures**: Session context usage
  - Current context tokens / 200K context window
  - Shows how full Claude's memory is
- **Purpose**: Display current session memory utilization
- **Data source**: `activeSession.tokens` (context tokens, not cumulative)

## Root Cause
The two UI components are intentionally showing different metrics:
1. **Status bar**: Billing/limit tracking (cost and token limits)
2. **Dropdown**: Memory/context tracking (session context usage)

## User Requirement
- Both status bar and dropdown should show the **same value**
- Specifically: Show the dropdown's "Overall" percentage (session context) in the status bar
- Both should refresh at the same time

## Technical Implications

### What Needs to Change
1. **MenuBarController.swift**:
   - Replace `calculateCriticalPercentage()` with session context calculation
   - Use same logic as dropdown's `calculateSessionBlockPercentage()`

2. **Ensure Synchronized Updates**:
   - Both components already use same `UsageViewModel`
   - Updates are batched through `UpdateCoordinator`
   - Should update simultaneously after change

### Current Update Mechanism
- **Polling**: 3s active, 10s idle (UpdateCoordinator.swift)
- **Batched updates**: All data operations complete before UI notification
- **Same data source**: Both read from `UsageViewModel`

## Risks and Considerations
1. **Loss of billing visibility**: Status bar will no longer show cost/limit tracking
2. **User confusion**: Other users may expect billing info in status bar
3. **Feature flag**: Consider making this configurable

## Recommendation
Implement the change but consider adding a setting to toggle between:
- "Session Context" mode (show memory usage)
- "Billing" mode (show cost/limit usage)
- This preserves both use cases