# Session Block Identification Logic - Detailed Analysis

**Date**: 2025-01-23
**Component**: SessionBlockCalculator.swift

## Overview

The session block logic groups Claude Code usage entries into **5-hour billing blocks** that correspond to Claude's actual billing periods. This ensures accurate cost tracking and burn rate calculations aligned with how Claude bills users.

## Core Concepts

### 1. Session Block Duration
- **Default**: 5 hours (300 minutes, 18,000 seconds)
- **Purpose**: Matches Claude's billing window
- **Configuration**: Can be customized via `sessionDurationHours` parameter

### 2. Block Types
- **Normal Block**: Contains actual usage entries within a 5-hour period
- **Gap Block**: Represents periods of inactivity longer than 5 hours
- **Active Block**: A block where the last activity was within the last 5 hours

## Block Identification Algorithm

### Step 1: Initial Setup
```swift
// Sort all entries chronologically
let sortedEntries = entries.sorted { entry1, entry2 in
    guard let date1 = entry1.date, let date2 = entry2.date else {
        return false
    }
    return date1 < date2
}
```

### Step 2: Block Start Time Calculation

The **start time** of a block is determined by **flooring to the hour**:

```swift
private static func floorToHour(_ date: Date) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
    return calendar.date(from: components) ?? date
}
```

**Example**:
- Entry timestamp: `2025-01-23 14:37:25`
- Block start time: `2025-01-23 14:00:00` (floored to hour)

### Step 3: Block Creation Rules

A new block is created when:

1. **First Entry**: The very first entry starts a new block
   ```swift
   if currentBlockStart == nil {
       currentBlockStart = floorToHour(entryTime)
       currentBlockEntries = [entry]
   }
   ```

2. **5-Hour Boundary Exceeded**: Entry is more than 5 hours from block start
   ```swift
   let timeSinceBlockStart = entryTime.timeIntervalSince(blockStart)
   if timeSinceBlockStart > sessionDurationSeconds {
       // Close current block and start new one
   }
   ```

3. **5-Hour Gap**: More than 5 hours since last activity
   ```swift
   let timeSinceLastEntry = entryTime.timeIntervalSince(lastEntryTime)
   if timeSinceLastEntry > sessionDurationSeconds {
       // Close current block, create gap block, start new block
   }
   ```

### Step 4: Gap Block Creation

Gap blocks are created when there's more than 5 hours of inactivity:

```swift
private static func createGapBlock(
    lastActivityTime: Date,
    nextActivityTime: Date,
    sessionDurationSeconds: TimeInterval
) -> SessionBlock? {
    let gapDuration = nextActivityTime.timeIntervalSince(lastActivityTime)
    guard gapDuration > sessionDurationSeconds else {
        return nil
    }

    let gapStart = lastActivityTime.addingTimeInterval(sessionDurationSeconds)
    let gapEnd = nextActivityTime

    return SessionBlock(
        id: "gap-\(formatter.string(from: gapStart))",
        startTime: gapStart,
        endTime: gapEnd,
        isGap: true,
        costUSD: 0,  // Gap blocks have no cost
        entries: []   // Gap blocks have no entries
    )
}
```

## Cost and Token Calculation Within Blocks

### Cost Aggregation Process

For each entry in a block, costs are calculated and summed:

```swift
for entry in entries {
    // Step 1: Determine cost for this entry
    let entryCost: Double
    if let existingCost = entry.costUSD, existingCost > 0 {
        // Use pre-calculated cost from JSONL if available
        entryCost = existingCost
    } else {
        // Calculate cost based on token usage and model pricing
        entryCost = ClaudeCostCalculator.calculateCost(
            tokens: entry.message.usage,
            model: entry.message.model ?? "claude-3-5-sonnet-20241022",
            mode: .auto,
            existingCost: entry.costUSD
        )
    }

    // Step 2: Add to block total
    costUSD += entryCost
}
```

### Token Aggregation

Tokens are summed across all entries in the block:

```swift
for entry in entries {
    inputTokens += entry.message.usage.input_tokens
    outputTokens += entry.message.usage.output_tokens
    cacheCreationInputTokens += entry.message.usage.cache_creation_input_tokens ?? 0
    cacheReadInputTokens += entry.message.usage.cache_read_input_tokens ?? 0
}
```

### Block Properties

Each block contains:
- **id**: ISO timestamp of block start (e.g., "2025-01-23T14:00:00Z")
- **startTime**: Floored to hour
- **endTime**: startTime + 5 hours
- **actualEndTime**: Timestamp of last entry in block
- **isActive**: true if last activity < 5 hours ago AND current time < endTime
- **isGap**: true for gap blocks
- **costUSD**: Sum of all entry costs
- **tokenCounts**: Aggregated tokens by type
- **models**: Set of all models used in block

## Practical Example

```
Timeline of entries:
09:15 - First entry (10K tokens, $0.50)
09:45 - Second entry (5K tokens, $0.25)
10:30 - Third entry (8K tokens, $0.40)
14:00 - Fourth entry (3K tokens, $0.15)  // > 5 hours gap
14:20 - Fifth entry (7K tokens, $0.35)

Results in blocks:
Block 1: 09:00-14:00 (start floored to hour)
  - Contains: entries 1-3
  - Total tokens: 23K
  - Total cost: $1.15
  - actualEndTime: 10:30

Gap Block: 14:00-14:00
  - No entries or costs
  - Represents inactivity period

Block 2: 14:00-19:00
  - Contains: entries 4-5
  - Total tokens: 10K
  - Total cost: $0.50
  - actualEndTime: 14:20
  - isActive: true (if current time < 19:00)
```

## Key Design Decisions

1. **Flooring to Hour**: Provides consistent, predictable block boundaries
2. **5-Hour Duration**: Matches Claude's billing period
3. **Gap Blocks**: Clearly distinguish inactive periods from active usage
4. **Cost Calculation Fallback**: Ensures all entries have costs, even if missing from JSONL
5. **UTC Timestamps**: Consistent timezone handling across all calculations

## Active Block Detection

A block is considered "active" if:
1. Last activity was less than 5 hours ago
2. Current time hasn't exceeded the block's natural end time

```swift
let isActive = now.timeIntervalSince(actualEndTime) < sessionDurationSeconds
            && now < endTime
```

This ensures burn rate calculations only apply to currently active sessions.

## Burn Rate Calculation

Once blocks are created with aggregated costs and tokens:

```swift
let durationMinutes = block.actualEndTime.timeIntervalSince(block.startTime) / 60
let tokensPerMinute = totalTokens / durationMinutes
let costPerHour = (block.costUSD / durationMinutes) * 60
```

The burn rate represents the average usage rate within that specific block, which can be used for predictions and monitoring.