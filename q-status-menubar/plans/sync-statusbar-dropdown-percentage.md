# Implementation Plan: Synchronize Status Bar and Dropdown Percentages

## Objective
Make the Mac status bar show the same percentage as the dropdown's "Overall" value (session context usage) instead of the critical billing percentage.

## Current State
- **Status Bar**: Shows 22% (critical billing percentage - max of token/cost usage)
- **Dropdown**: Shows 54% (session context usage - tokens in memory / 200K)
- **Issue**: Different metrics being displayed

## Target State
- Both status bar and dropdown show the same percentage
- Both display session context usage (current tokens / context window)
- Both update simultaneously

## Implementation Phases

### Phase 1: Update MenuBarController Calculation ✓
**Objective**: Replace critical percentage with session context percentage in status bar

**Tasks**:
- [x] Modify `updateTitleAndIcon()` in MenuBarController.swift
- [x] Replace `PercentageCalculator.calculateCriticalPercentage()` call
- [x] Use session context calculation matching dropdown logic
- [x] Maintain all icon modes functionality

**Code Changes**:
```swift
// Replace lines 53-60 in MenuBarController.swift
// Old: criticalPct = PercentageCalculator.calculateCriticalPercentage(...)
// New: Use session context calculation
let criticalPct: Double
if let activeSession = vm.activeClaudeSession {
    let contextWindow = settings.claudeTokenLimit ?? 200_000
    criticalPct = PercentageCalculator.calculateTokenPercentage(
        tokens: activeSession.tokens,
        limit: contextWindow
    )
} else {
    criticalPct = 0
}
```

**Success Criteria**:
- Status bar shows session context percentage
- All icon modes still function correctly
- Code compiles without errors

### Phase 2: Add Fallback for No Active Session ✓
**Objective**: Provide meaningful display when no active session exists

**Tasks**:
- [x] Determine fallback behavior when no active session
- [x] Option 1: Show 0%
- [x] Option 2: Show monthly usage percentage (SELECTED)
- [x] Option 3: Show last known session percentage

**Recommended Approach**:
```swift
let criticalPct: Double
if let activeSession = vm.activeClaudeSession {
    // Active session: show context usage
    let contextWindow = settings.claudeTokenLimit ?? 200_000
    criticalPct = PercentageCalculator.calculateTokenPercentage(
        tokens: activeSession.tokens,
        limit: contextWindow
    )
} else if settings.claudePlan.costLimit > 0 {
    // No active session: show monthly usage as fallback
    criticalPct = PercentageCalculator.calculateTokenPercentage(
        tokens: vm.tokensMonth,
        limit: settings.claudePlan.tokenLimit ?? 10_000_000
    )
} else {
    // No data available
    criticalPct = 0
}
```

**Success Criteria**:
- Graceful handling when no session is active
- Meaningful fallback percentage displayed
- No UI glitches or empty states

### Phase 3: Verify Update Synchronization
**Objective**: Ensure both components update at exactly the same time

**Tasks**:
- [ ] Verify both components use same ViewModel properties
- [ ] Confirm batched updates apply to both
- [ ] Test update timing under various conditions
- [ ] Add logging if needed for verification

**Verification Points**:
- Both read `vm.activeClaudeSession.tokens`
- Both use same context window limit
- Both receive updates from same `onUIUpdate` callback

**Success Criteria**:
- Percentages match exactly between status bar and dropdown
- Updates occur simultaneously
- No timing delays or discrepancies

### Phase 4: Add Configuration Option (Optional Enhancement)
**Objective**: Allow users to choose between session context and billing display

**Tasks**:
- [ ] Add setting to toggle display mode
- [ ] Create enum: `.sessionContext` vs `.billingUsage`
- [ ] Update MenuBarController to respect setting
- [ ] Add UI control in Preferences

**Implementation**:
```swift
enum StatusBarDisplayMode {
    case sessionContext  // Show memory usage (new behavior)
    case billingUsage   // Show cost/limit (old behavior)
}

// In Settings
var statusBarDisplayMode: StatusBarDisplayMode = .sessionContext

// In MenuBarController
let criticalPct: Double
switch settings.statusBarDisplayMode {
case .sessionContext:
    // New behavior - session context
case .billingUsage:
    // Original behavior - critical percentage
}
```

**Success Criteria**:
- Users can toggle between display modes
- Setting persists across app restarts
- Clear labeling in preferences

### Phase 5: Testing and Validation
**Objective**: Thoroughly test the implementation

**Test Cases**:
- [ ] With active Claude session - verify matching percentages
- [ ] Without active session - verify fallback behavior
- [ ] During session start/stop - verify smooth transitions
- [ ] With multiple rapid updates - verify synchronization
- [ ] Different icon modes - verify all display correctly

**Validation Steps**:
1. Start app with no active session
2. Begin Claude Code session
3. Monitor percentage in both locations
4. Use Claude actively to change context usage
5. Verify percentages remain synchronized
6. Stop session and verify fallback

**Success Criteria**:
- All test cases pass
- No regressions in existing functionality
- Percentages always match between UI components

## Risk Mitigation

### Risks
1. **Loss of billing visibility**: Users won't see cost/limit tracking in status bar
2. **Breaking change**: Existing users expect billing info
3. **Confusion**: Different users have different needs

### Mitigation Strategies
1. Consider configuration option (Phase 4)
2. Document change in release notes
3. Preserve original calculation logic for future use

## Rollback Plan
If issues arise:
1. Revert MenuBarController.swift changes
2. Restore original `calculateCriticalPercentage()` call
3. Original calculation logic remains in PercentageCalculator

## Timeline
- Phase 1: 10 minutes (core change)
- Phase 2: 5 minutes (fallback logic)
- Phase 3: 10 minutes (verification)
- Phase 4: 20 minutes (optional configuration)
- Phase 5: 15 minutes (testing)

**Total: ~40-60 minutes**