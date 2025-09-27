# Implementation Plan: Three UI Improvements

## Overview
Three independent UI improvements to be implemented in the Q-Status menubar application.

## Feature 1: Add Manual Refresh Button

### Objective
Add a manual refresh button to the dropdown view for on-demand data updates.

### Implementation Details
- **Location**: `controlButtonsSection` in DropdownView.swift
- **Method**: Use existing `viewModel.forceRefresh?()` callback
- **Icon**: SF Symbol `arrow.clockwise`
- **Placement**: Between Spacer and Pause button

### Code Changes
```swift
// In controlButtonsSection
Button(action: { viewModel.forceRefresh?() }) {
    Image(systemName: "arrow.clockwise")
        .font(.system(size: 12))
}
.help("Refresh now")
```

### Success Criteria
- [x] Button appears in control section
- [x] Click triggers manual refresh
- [x] Tooltip shows on hover

## Feature 2: Fix Cost Calculations

### Objective
Fix $0 cost display for rolling 30-day and 7-day periods despite token usage.

### Root Cause
`fetchPeriodTokensByModel` method only uses pre-calculated costs from JSONL, doesn't fall back to ClaudeCostCalculator.

### Implementation Details
- **File**: ClaudeCodeDataSource.swift
- **Method**: `fetchPeriodTokensByModel`
- **Line**: ~549
- **Fix**: Add fallback to ClaudeCostCalculator when JSONL cost is nil

### Code Changes
```swift
// Replace line 549
let entryCost = entry.costUSD ?? 0.0

// With:
let entryCost: Double
if let jsonlCost = entry.costUSD, jsonlCost > 0 {
    entryCost = jsonlCost
} else {
    let model = entry.message.model ?? "claude-3-5-sonnet-20241022"
    entryCost = ClaudeCostCalculator.calculateCost(
        tokens: entry.message.usage,
        model: model,
        mode: costMode,
        existingCost: entry.costUSD
    )
}
```

### Success Criteria
- [x] 30-day costs show actual values
- [x] 7-day costs show actual values
- [x] Debug logs stop showing "cost is zero but tokens exist"

## Feature 3: Update Recent Sessions Label

### Objective
Change "Recent Sessions" label to "Context: Recent sessions" in dropdown.

### Implementation Details
- **File**: DropdownView.swift
- **Line**: 480
- **Change**: Simple string replacement

### Code Changes
```swift
// Line 480
Text("Context: Recent sessions")
```

### Success Criteria
- [x] Label shows "Context: Recent sessions"
- [x] Styling remains unchanged
- [x] Section functionality unchanged

## Testing Plan
1. Build project
2. Run application
3. Verify refresh button works
4. Check cost calculations display correctly
5. Confirm label text updated

## Risk Assessment
- **Low risk**: All changes are isolated
- **No breaking changes**: Uses existing infrastructure
- **Backward compatible**: No data structure changes