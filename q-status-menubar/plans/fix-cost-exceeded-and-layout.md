# Implementation Plan: Fix Cost Exceeded Logic and Optimize Dropdown Layout

## Issue 1: Cost Exceeded Message Shows Incorrectly

### Problem
- Shows "Cost limit exceeded!" when cost is only 13% ($19.33/$140)
- Uses wrong calculation: compares against $0.97 session limit instead of $140 baseline
- Inconsistent with the percentage display

### Current Logic (WRONG)
```swift
// Line 1878-1886 in DropdownView.swift
let sessionLimit = (plan.costLimit / 30.0) * (5.0 / 24.0)  // ~$0.97
if projectedSessionCost > sessionLimit * 1.5  // Triggers at ~$1.46
```

### Fix Required
Use the same calculation as the percentage display:
```swift
let costPercentage = PercentageCalculator.calculateCostPercentage(
    cost: projectedSessionCost,
    useBlockBaseline: true
)
if costPercentage > 100  // Only show when actually exceeded
```

## Issue 2: Dropdown Height Exceeds 15" Laptop Screen

### Problem
- Fixed at 500x400px, content overflows
- All sections stacked vertically
- Takes up full screen height on smaller displays

### Current Dimensions
- MenuBarController: 500x400px
- DropdownView: .frame(width: 500)

### Solution
- Increase width: 500px → 700px
- Reduce height: 400px → 350px
- Implement 2-column layout for better space usage

### Layout Changes
1. **Left Column (300px)**:
   - Global header
   - Claude Code section
   - Active session

2. **Right Column (400px)**:
   - Recent sessions
   - Controls
   - Data source selector

## Implementation Steps

### Step 1: Fix Cost Exceeded Logic
1. Locate burnRateAndPredictions() function
2. Replace sessionLimit calculation with percentage-based check
3. Use PercentageCalculator.calculateCostPercentage()

### Step 2: Optimize Layout
1. Update MenuBarController popover size to 700x350
2. Modify DropdownView to use HStack for columns
3. Reorganize sections into left/right columns
4. Test on different screen sizes

## Success Criteria
- [ ] Cost exceeded only shows when >100% ($140+ spent)
- [ ] Dropdown fits within 15" laptop screen
- [ ] Width increased to 700px
- [ ] Height reduced to 350px or less
- [ ] Two-column layout implemented