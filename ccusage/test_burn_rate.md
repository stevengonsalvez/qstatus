# Burn Rate Display Testing Guide

## Implementation Summary

A comprehensive burn rate display with predictions has been added to the Claude Code section of the DropdownView. The feature includes:

### 1. Data Model Changes
- Added `costPerHour: Double` field to `ActiveSessionData` struct
- Calculate cost burn rate alongside token and message burn rates in `ClaudeCodeDataSource.fetchActiveSession()`

### 2. New BurnRateView Component
Created a new SwiftUI component `BurnRateView` with the following features:

#### Burn Rate Display
- **Token burn rate**: Displays in tokens/hr, K/hr, or K/min based on rate
- **Cost burn rate**: Displays in $/day, $/hr based on rate
- **Message burn rate**: Displays in msgs/day, msgs/hr, or msgs/min based on rate

#### Smart Unit Selection
- Very low rates show per day
- Moderate rates show per hour
- High rates show per minute or with K notation

#### Predictions
Calculates when limits will be reached:
- **Context limit**: Based on context token growth (estimated at 20% of cumulative rate)
- **Cost limit**: Based on monthly plan limit and current burn rate
- **Message limit**: Based on 5000/month quota

#### Visual Design
- Compact GroupBox with flame icon
- Grid layout for burn rates
- Color-coded predictions (red < 6hr, orange < 24hr, yellow > 24hr)
- Only shows after 1 minute of session activity

### 3. Integration
- Added below the three progress bars in active session view
- Only displays for Claude Code data source
- Hidden if no active session or session < 1 minute old

## Test Scenarios

### Scenario 1: Low Usage Rate
- Session running for 2 hours
- 1000 tokens used (500 tokens/hr)
- 2 messages sent (1 msg/hr)
- Expected: Shows "500 tokens/hr", "1.0 msgs/hr", predictions in days

### Scenario 2: High Usage Rate
- Session running for 30 minutes
- 30000 tokens used (60K tokens/hr)
- 60 messages sent (120 msgs/hr)
- Expected: Shows "60.0 K/hr", "2.0 msgs/min", predictions in hours

### Scenario 3: Critical Usage
- Near context limit (180K of 200K)
- High burn rate (10K tokens/hr)
- Expected: Red warning "Context limit in ~2 hrs"

### Scenario 4: Cost Predictions
- Pro plan ($18/month limit)
- $15 already spent this month
- $0.50/hr burn rate
- Expected: "Cost limit in ~6 hrs" in orange

## Files Modified

1. `/Users/stevengonsalvez/d/git/qlips/q-status-menubar/Sources/Core/ClaudeCodeDataSource.swift`
   - Added `costPerHour` field to `ActiveSessionData`
   - Calculate cost burn rate in `fetchActiveSession()`

2. `/Users/stevengonsalvez/d/git/qlips/q-status-menubar/Sources/App/DropdownView.swift`
   - Added new `BurnRateView` component (lines 1317-1529)
   - Integrated into active session display (lines 430-438)

## Visual Layout

```
┌──────────────────────────────────────┐
│ 🔥 Burn Rate & Predictions           │
├──────────────────────────────────────┤
│ 🔥 Tokens        12.5 K/hr           │
│ 💲 Cost          $0.032/hr           │
│ 💬 Messages      15.2 msgs/hr        │
├──────────────────────────────────────┤
│ ⚠️ Context limit in ~8 hrs          │
│ 💲 Cost limit in ~3 days            │
│ 💬 Message limit in ~12 hrs         │
└──────────────────────────────────────┘
```

## Known Limitations

1. Context growth rate is estimated at 20% of cumulative token rate (heuristic)
2. Predictions assume constant burn rate
3. Only shows for paid Claude plans (free plan has no predictions)
4. Requires at least 1 minute of session activity to display

## Future Enhancements

1. Track actual context growth rate over time for better predictions
2. Add historical burn rate trends
3. Include daily/weekly cost projections
4. Add configurable warning thresholds
5. Support for custom plan limits