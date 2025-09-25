# Fix Plan: Percentage Synchronization and Code Deduplication

**Created**: 2025-01-24
**Objective**: Fix percentage calculation discrepancies between status bar and dropdown, eliminate duplicate logic

## Problem Summary
1. ClaudeCodeDataSource still uses old percentage calculation (contextTokens/200K)
2. Sequential async updates create timing windows with inconsistent data
3. onUIUpdate notifications don't fire for all data changes
4. Duplicate percentage calculation logic in multiple places

## Success Criteria
- [ ] Status bar and dropdown always show identical percentages
- [ ] Single source of truth for percentage calculations
- [ ] All updates are atomic and properly notified
- [ ] No duplicate calculation logic remains

## Implementation Phases

### Phase 1: Create Centralized Percentage Calculator
**Objective**: Single source of truth for all percentage calculations

- [ ] Create new `PercentageCalculator` struct/class
- [ ] Move calculation logic from MenuBarController.calculateCriticalPercentage()
- [ ] Add methods for token, cost, and critical percentages
- [ ] Use consistent baselines (personalMax or 10M for tokens, $140 for cost)

### Phase 2: Update ClaudeCodeDataSource Calculations
**Objective**: Fix the root cause - incorrect data source calculations

- [ ] Import/use the new PercentageCalculator
- [ ] Fix line 333: Replace `Double(contextTokens) / Double(defaultContextWindow) * 100`
- [ ] Fix line 376: Replace duplicate calculation
- [ ] Fix line 433: Replace session.totalTokens calculation
- [ ] Ensure all SessionSummary objects use new calculation

### Phase 3: Fix Update Notification System
**Objective**: Ensure all UI components are notified of changes

- [ ] Add onUIUpdate call after refreshActiveClaudeSession() completes
- [ ] Ensure onUIUpdate fires after refreshGlobalTotals()
- [ ] Consider consolidating multiple update calls into one

### Phase 4: Make Updates Atomic
**Objective**: Prevent race conditions from partial updates

- [ ] Batch viewModel updates in single MainActor.run block
- [ ] Update activeClaudeSession and maxTokensFromPreviousBlocks together
- [ ] Ensure all @Published properties update atomically

### Phase 5: Update All UI Components
**Objective**: Use centralized calculator everywhere

- [ ] Update MenuBarController to use PercentageCalculator
- [ ] Update DropdownView to use PercentageCalculator
- [ ] Remove calculateCriticalPercentage() from MenuBarController
- [ ] Remove duplicate percentage logic from DropdownView

### Phase 6: Optimize Update Sequence
**Objective**: Improve synchronization timing

- [ ] Consider using TaskGroup for parallel updates
- [ ] Reorder update sequence for better data consistency
- [ ] Add debouncing if needed to prevent flickering

## Verification Steps
1. Build the project successfully
2. Run the app and verify percentages match
3. Test with active sessions and blocks
4. Test transitions between blocks
5. Verify refresh triggers update both components
6. Check for any remaining duplicate logic

## Risk Mitigation
- Test each phase independently before proceeding
- Keep old calculation methods commented until verified
- Add logging to track calculation differences
- Create unit tests for PercentageCalculator

## Code Locations to Modify
- `Sources/Core/ClaudeCodeDataSource.swift`: Lines 333, 376, 433
- `Sources/Core/UpdateCoordinator.swift`: Lines 80, 106, 178, 448-451
- `Sources/App/MenuBarController.swift`: Lines 54, 190-222
- `Sources/App/DropdownView.swift`: Lines 2005-2031
- New file: `Sources/Core/PercentageCalculator.swift`

## Dependencies
- Phase 1 must complete before Phases 2 and 5
- Phases 2-4 can be done in parallel
- Phase 5 depends on Phase 1
- Phase 6 should be done last