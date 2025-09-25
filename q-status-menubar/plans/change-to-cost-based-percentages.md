# Implementation Plan: Change Both Percentages to Cost-Based Calculation

## Objective
Change both the status bar and dropdown percentages to show cost vs $140 baseline instead of context usage vs 200K tokens.

## Current Problem
- Status bar shows: context tokens / 200K (memory usage)
- Dropdown shows: context tokens / 200K (memory usage)
- User wants: cost / $140 baseline (billing usage)

## Implementation Details

### Change 1: Revert MenuBarController.swift
**File**: Sources/App/MenuBarController.swift
**Lines**: 53-72

**Current Code** (showing context usage):
```swift
let criticalPct: Double
if let activeSession = vm.activeClaudeSession {
    let contextWindow = settings.claudeTokenLimit
    criticalPct = PercentageCalculator.calculateTokenPercentage(
        tokens: activeSession.tokens,
        limit: contextWindow
    )
} // ... fallback logic
```

**Replace With** (original cost-based):
```swift
let monthlyData = settings.claudePlan.costLimit > 0 ?
    (cost: vm.costMonth, limit: settings.claudePlan.costLimit) : nil
let criticalPct = PercentageCalculator.calculateCriticalPercentage(
    activeSession: vm.activeClaudeSession,
    maxTokensFromPreviousBlocks: vm.maxTokensFromPreviousBlocks,
    monthlyData: monthlyData
)
```

### Change 2: Update DropdownView.swift
**File**: Sources/App/DropdownView.swift
**Method**: calculateSessionBlockPercentage (lines 1086-1103)

**Changes Required**:
1. Replace token-based calculation with cost-based
2. Use PercentageCalculator.calculateCostPercentage
3. Update comments to reflect cost calculation
4. Remove unused contextWindow variable

**New Implementation**:
```swift
private func calculateSessionBlockPercentage(plan: ClaudePlan) -> (percent: Double, tokens: Int, cost: Double) {
    if let activeSession = viewModel.activeClaudeSession {
        let contextTokens = activeSession.tokens
        let cost = activeSession.cost

        // Calculate cost percentage against $140 baseline
        let percent = PercentageCalculator.calculateCostPercentage(
            cost: cost,
            useBlockBaseline: true
        )

        return (percent, contextTokens, cost)
    } else {
        return (0, 0, 0)
    }
}
```

## Expected Behavior After Changes

Both status bar and dropdown will show:
- **Primary**: Cost percentage (currentCost / $140) × 100
- **Fallback**: If cost% < token%, may show token% (via calculateCriticalPercentage)
- **Baseline**: $140 for 5-hour blocks
- **Identical values**: Both UI elements show same percentage

## Success Criteria
- [ ] Status bar shows cost vs $140 baseline
- [ ] Dropdown shows cost vs $140 baseline
- [ ] Both show identical percentages
- [ ] Tooltips show cost information when cost is critical metric