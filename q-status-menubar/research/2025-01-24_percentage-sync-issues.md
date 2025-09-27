# Research: Status Bar and Dropdown Percentage Synchronization Issues

**Date**: 2025-01-24
**Repository**: q-status-menubar
**Branch**: feat/cc
**Research Type**: Comprehensive Codebase Analysis

## Research Question
Are the status bar and dropdown truly using the same percentage values and refresh intervals? Why are there still visible differences?

## Executive Summary
While both UI components have been updated to use the same calculation logic, **critical issues remain** that cause visible discrepancies: (1) The underlying data source still uses the old percentage calculation method, (2) Sequential async operations create timing windows where components show different data, and (3) The update notification system doesn't fire consistently for all data changes.

## Key Findings
1. **Old calculation method still active in data source** - ClaudeCodeDataSource.swift still calculates SessionSummary.usagePercent using contextTokens/200K
2. **Sequential async updates create delays** - Status bar updates before active session data is available
3. **Missing update notifications** - onUIUpdate callback only fires from append(), not from other critical updates
4. **Non-atomic property updates** - Race conditions when updating multiple @Published properties

## Detailed Findings

### 1. Critical Bug: Old Percentage Calculation Still Active

#### Location: ClaudeCodeDataSource.swift
The data source is still creating `SessionSummary` objects with the old percentage calculation:

**Line 333:**
```swift
let usagePercent = Double(contextTokens) / Double(defaultContextWindow) * 100
```

**Line 376:**
```swift
let usagePercent = Double(contextTokens) / Double(defaultContextWindow) * 100
```

**Line 433:**
```swift
let usagePercent = Double(session.totalTokens) / Double(defaultContextWindow) * 100
```

These calculate percentages using `defaultContextWindow = 200,000` instead of our new block-based logic.

### 2. Timing and Synchronization Issues

#### Sequential Update Operations
**UpdateCoordinator.swift:72-80**
```swift
await self.append(snapshot: snapshot)            // Updates status bar first
await self.applySessions(sessions)               // Updates sessions list
await self.refreshGlobalTotals()                 // Updates global metrics
await self.refreshActiveClaudeSession()          // Updates active session last
```

**Problem**: The status bar receives updates via `onUIUpdate` immediately after `append()`, but the active session data (needed for correct percentage calculation) isn't available until the final async call completes.

#### Race Condition in Property Updates
**UpdateCoordinator.swift:448-451**
```swift
await MainActor.run {
    viewModel.activeClaudeSession = activeSession        // First update
    viewModel.maxTokensFromPreviousBlocks = maxTokens   // Second update
}
```

**Problem**: SwiftUI can trigger view updates between these property assignments, causing calculations with partially stale data.

### 3. Inconsistent Update Notifications

#### Only append() Triggers UI Updates
**UpdateCoordinator.swift:178**
```swift
onUIUpdate?(viewModel)  // Only called from append()
```

**Problem**: Critical updates from `refreshActiveClaudeSession()` don't trigger status bar updates, leading to stale display until the next polling cycle.

### 4. Refresh Mechanism Analysis

#### Unified Polling System
- **Base interval**: 3 seconds (Settings.swift:106)
- **Adaptive scaling**: Increases to max 5 seconds when stable (UpdateCoordinator.swift:88-90)
- **Single update pipeline**: Both components should update together

#### However, timing issues cause desynchronization:
1. Status bar updates immediately on `append()`
2. Dropdown data arrives later after `refreshActiveClaudeSession()`
3. No notification fires when active session updates complete

## Architecture Insights

### Data Flow Pattern
```
UpdateCoordinator.start()
    ↓ (every 3-5 seconds)
fetchLatestUsage()
    ↓
append() → onUIUpdate → MenuBarController.updateIcon()
    ↓
applySessions()
    ↓
refreshGlobalTotals()
    ↓
refreshActiveClaudeSession() → Updates viewModel properties
    ↓
(No onUIUpdate call - status bar not notified!)
```

### Component Dependencies
- **MenuBarController**: Relies on `onUIUpdate` callback
- **DropdownView**: Observes @Published properties directly
- **Problem**: Different update mechanisms lead to different timing

## Code References
- `ClaudeCodeDataSource.swift:333,376,433` - Old percentage calculations still active
- `UpdateCoordinator.swift:72-80` - Sequential async operations causing delays
- `UpdateCoordinator.swift:178` - Only update notification point
- `UpdateCoordinator.swift:448-451` - Non-atomic property updates
- `MenuBarController.swift:21-23` - Status bar update callback registration
- `MenuBarController.swift:181-213` - calculateCriticalPercentage implementation
- `DropdownView.swift:2005-2031` - Dropdown percentage calculations

## Recommendations

### Immediate Fixes Needed
1. **Fix ClaudeCodeDataSource.swift** - Update lines 333, 376, 433 to use new block-based percentage calculation
2. **Add onUIUpdate calls** - Fire callback from `refreshActiveClaudeSession()` and other update methods
3. **Make updates atomic** - Batch all viewModel property updates in single MainActor.run block

### Architectural Improvements
1. **Use TaskGroup** for parallel updates instead of sequential awaits
2. **Implement update sequence numbers** to ensure UI consistency
3. **Add debouncing** to prevent partial state displays
4. **Create single source of truth** for percentage calculation

## Root Cause Summary
The discrepancies occur because:
1. The underlying data still uses old calculation methods in some places
2. Sequential async operations create timing windows where components have different data
3. The notification system doesn't consistently inform all UI components of updates
4. Non-atomic updates allow partial state to be observed

## Next Steps
1. Update ClaudeCodeDataSource to use new percentage calculation consistently
2. Ensure onUIUpdate fires after ALL data updates, not just append()
3. Make viewModel updates atomic to prevent race conditions
4. Consider refactoring to parallel update operations for better synchronization