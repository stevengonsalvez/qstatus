# Research: ccusage vs q-status-menubar Session Block Calculation Comparison

**Date**: 2025-01-23 22:35:00
**Repository**: qlips
**Branch**: feat/cc
**Research Type**: Codebase Comparison

## Research Question
How does ccusage calculate session blocks and costs compared to q-status-menubar?

## Executive Summary
Both ccusage (TypeScript CLI) and q-status-menubar (Swift macOS app) implement the same core 5-hour billing block algorithm with identical logic for session identification, gap detection, and cost aggregation. The main differences lie in implementation details: ccusage offers more sophisticated cost calculation modes with live pricing integration, while q-status-menubar focuses on real-time monitoring with simpler pre-calculated costs.

## Key Findings
- **Same Algorithm**: Both use identical 5-hour billing blocks with UTC hour-floored start times
- **Gap Detection**: Both create gap blocks for >5 hour periods of inactivity
- **Cost Modes**: ccusage has 3 modes (auto/calculate/display) vs q-status-menubar's simpler approach
- **Pricing Data**: ccusage fetches from LiteLLM API vs q-status-menubar uses hardcoded/JSONL values
- **Implementation**: TypeScript (ccusage) vs Swift (q-status-menubar) with equivalent logic

## Detailed Findings

### Core Algorithm - Identical Implementation

#### Session Block Duration
**Both use 5-hour blocks:**

**ccusage** (`/ccusage/src/_session-blocks.ts`):
```typescript
const DEFAULT_SESSION_DURATION_HOURS = 5;
```

**q-status-menubar** (`SessionBlockCalculator.swift:7`):
```swift
public let DEFAULT_SESSION_DURATION_HOURS: Double = 5
```

#### Start Time Calculation - Both Floor to Hour
**ccusage** (TypeScript):
```typescript
function floorToHour(date: Date): Date {
  const d = new Date(date);
  d.setUTCMinutes(0, 0, 0);
  return d;
}
```

**q-status-menubar** (`SessionBlockCalculator.swift:78-84`):
```swift
private static func floorToHour(_ date: Date) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
    return calendar.date(from: components) ?? date
}
```

#### Block Creation Conditions - Identical Logic
Both create new blocks when:
1. First entry encountered (starts new block)
2. Entry is >5 hours from current block start
3. Entry is >5 hours since last activity (gap detected)

#### Gap Detection - Same Algorithm
Both systems:
- Create gap blocks only when gap > 5 hours
- Gap starts at: `lastActivity + 5 hours`
- Gap ends at: `nextActivity`
- Gap blocks have no entries and zero cost

### Session Identification

#### ccusage Approach
Groups by either:
1. Explicit `sessionId` from JSONL filename
2. `projectPath + 5-hour time blocks` fallback

#### q-status-menubar Approach (`ClaudeCodeDataSource.swift:725-750`)
Groups by either:
1. Explicit `sessionId` if available
2. `cwd + 5-hour time blocks` fallback

**Result**: Functionally equivalent grouping strategies

### Cost Calculation Differences

#### ccusage - Three-Mode System
```typescript
// From ccusage/src/_types.ts:103-112
type CostMode = 'auto' | 'calculate' | 'display';
```

1. **`auto`** (default): Uses JSONL `costUSD` if available, else calculates
2. **`calculate`**: Always calculates from tokens × model pricing
3. **`display`**: Only uses pre-calculated `costUSD`, shows 0 if missing

#### q-status-menubar - Simple Fallback
```swift
// From SessionBlockCalculator.swift:201-213
let entryCost: Double
if let existingCost = entry.costUSD, existingCost > 0 {
    entryCost = existingCost
} else {
    entryCost = ClaudeCostCalculator.calculateCost(...)
}
```

**Result**: q-status-menubar essentially implements ccusage's "auto" mode only

### Pricing Data Sources

#### ccusage
- **Primary**: Live fetch from LiteLLM API
- **URL**: `https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json`
- **Fallback**: Pre-fetched cached data for offline mode
- **Update**: Can refresh pricing dynamically

#### q-status-menubar
- **Primary**: Hardcoded pricing in `ClaudeCostCalculator.swift:87-167`
- **Secondary**: `model_prices.json` resource file
- **Fallback**: Uses JSONL `costUSD` when available
- **Update**: Requires app update for new pricing

### Token Type Handling - Identical

Both handle all 4 token types:

| Token Type | ccusage | q-status-menubar |
|------------|---------|------------------|
| Input | ✅ `input_tokens` | ✅ `inputTokens` |
| Output | ✅ `output_tokens` | ✅ `outputTokens` |
| Cache Creation | ✅ `cache_creation_input_tokens` | ✅ `cacheCreationInputTokens` |
| Cache Read | ✅ `cache_read_input_tokens` | ✅ `cacheReadInputTokens` |

### Aggregation Capabilities

#### ccusage - Multiple Time Periods
- Daily (`YYYY-MM-DD`)
- Weekly (week start date)
- Monthly (`YYYY-MM`)
- Session (by project path)
- 5-hour blocks
- Live monitoring mode

#### q-status-menubar - Real-Time Focus
- 5-hour blocks
- Active session tracking
- Burn rate calculations
- Context limit predictions
- Plan usage percentages

### Architecture Comparison

| Aspect | ccusage | q-status-menubar |
|--------|---------|------------------|
| **Language** | TypeScript/Node.js | Swift |
| **Type** | CLI tool | macOS menubar app |
| **Runtime** | Node/Bun | Native macOS |
| **UI** | Terminal tables | SwiftUI |
| **Update Frequency** | On-demand | Every 3 seconds |
| **Data Source** | JSONL files | JSONL files |
| **Testing** | Vitest | XCTest |

### Activity Detection Thresholds

Both use identical thresholds:
- **Recent session**: Activity within last **5 hours**
- **Active session**: Activity within last **30 minutes** (q-status-menubar only)
- **Block active**: Last activity < 5 hours AND current time < block end

### Burn Rate Calculations - Similar Approach

#### ccusage
```typescript
const durationMinutes = block.duration / 60;
const tokensPerMinute = block.totalTokens / durationMinutes;
const costPerHour = (block.cost / durationMinutes) * 60;
```

#### q-status-menubar
```swift
let durationMinutes = lastEntry.timeIntervalSince(firstEntry) / 60
let tokensPerMinute = totalTokens / durationMinutes
let costPerHour = (block.costUSD / durationMinutes) * 60
```

**Result**: Identical formulas, different syntax

## Architecture Insights

### Shared Design Decisions
1. **5-hour billing blocks**: Both align with Claude's actual billing periods
2. **UTC hour flooring**: Provides consistent, predictable block boundaries
3. **Gap detection**: Both identify and mark periods of inactivity
4. **Token aggregation**: Sum all token types for complete usage picture
5. **Cost fallback**: Both can calculate costs when not provided in JSONL

### Different Priorities
- **ccusage**: Flexibility (multiple modes), offline capability, batch analysis
- **q-status-menubar**: Real-time monitoring, UI integration, simplicity

## Code References

### ccusage
- `ccusage/src/_session-blocks.ts` - Core block algorithm
- `ccusage/src/data-loader.ts` - Data loading and parsing
- `ccusage/src/calculate-cost.ts` - Cost calculations
- `ccusage/src/pricing-fetcher.ts` - LiteLLM pricing integration

### q-status-menubar
- `q-status-menubar/Sources/Core/SessionBlockCalculator.swift:92-173` - Block identification
- `q-status-menubar/Sources/Core/ClaudeCodeDataSource.swift:725-750` - Session grouping
- `q-status-menubar/Sources/Core/ClaudeCostCalculator.swift:181-241` - Cost calculation

## Recommendations

Based on this research:

1. **Consider adding cost modes to q-status-menubar** - The 3-mode system from ccusage provides flexibility
2. **Implement LiteLLM pricing integration** - Would keep pricing current without app updates
3. **Add offline pricing cache** - ccusage's approach ensures functionality without internet
4. **Unify the implementations** - Consider sharing core logic via a common library
5. **Add weekly/monthly aggregation views** - ccusage's multiple time periods are useful

## Conclusions

The core session block algorithms are **functionally identical** between ccusage and q-status-menubar, demonstrating a consistent understanding of Claude's billing model. The main differences are:

1. **Implementation language** (TypeScript vs Swift)
2. **Cost calculation sophistication** (3 modes vs simple fallback)
3. **Pricing data management** (dynamic vs static)
4. **UI presentation** (CLI tables vs macOS menubar)
5. **Use case focus** (batch analysis vs real-time monitoring)

Both implementations correctly handle:
- 5-hour billing blocks
- UTC hour-floored timestamps
- Gap detection and marking
- All 4 token types
- Cost aggregation

The implementations are complementary: ccusage excels at detailed analysis and reporting, while q-status-menubar provides excellent real-time monitoring and macOS integration.

## References
- ccusage source: `/Users/stevengonsalvez/d/git/qlips/ccusage/`
- q-status-menubar source: `/Users/stevengonsalvez/d/git/qlips/q-status-menubar/`
- Previous analysis: `research/2025-01-23_session-block-logic.md`