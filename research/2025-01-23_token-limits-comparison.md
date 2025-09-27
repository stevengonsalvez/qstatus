# Token Limits Comparison: ccusage vs q-status-menubar

**Date**: 2025-01-23
**Research Focus**: Maximum token limits and how they're calculated

## Executive Summary

The key difference: **ccusage uses 200K (technical context window)** while **q-status-menubar uses both 200K (context) and 220K (plan limit)**. This is not a discrepancy but rather different purposes - ccusage focuses on per-session technical limits while q-status-menubar also tracks monthly subscription quotas.

## Token Limit Implementation Comparison

### ccusage Approach

#### Data Source
- **Primary**: LiteLLM API (`https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json`)
- **Fields**: Uses `max_input_tokens` (200K) with fallback to `max_tokens`
- **Dynamic**: Fetches live data for each model

#### Implementation (`pricing-fetcher.ts`)
```typescript
async getModelContextLimit(modelName: string) {
    const pricing = await this.getModelPricing(modelName);
    const contextLimit = pricing.max_input_tokens ?? pricing.max_tokens;
    return contextLimit; // Returns 200,000 for Claude models
}
```

#### Fallback Logic (`data-loader.ts`)
```typescript
let contextLimit = 200_000; // Fallback when model unknown
if (modelId != null) {
    const result = await fetcher.getModelContextLimit(modelId);
    if (result.success && result.value != null) {
        contextLimit = result.value; // Uses LiteLLM value (200K)
    }
}
```

#### What ccusage Reports
- **Claude 3.5 Sonnet**: 200,000 tokens (from `max_input_tokens`)
- **Claude 3 Opus**: 200,000 tokens (from `max_input_tokens`)
- **Purpose**: Technical context window (per-session limit)

### q-status-menubar Approach

#### Dual Limit System
q-status-menubar tracks TWO different types of limits:

1. **Context Window** (Technical Limit)
   - **Value**: 200,000 tokens
   - **Purpose**: Maximum tokens per conversation session
   - **Usage**: Session percentage calculations

2. **Plan Limits** (Subscription Quotas)
   - **Max20**: 220,000 tokens/month
   - **Max5**: 88,000 tokens/month
   - **Pro**: 19,000 tokens/month
   - **Purpose**: Monthly usage allowance

#### Implementation (`Settings.swift`)
```swift
public enum ClaudePlan {
    case max20

    var tokenLimit: Int {
        switch self {
        case .max20: return 220_000  // Plan limit
        // ...
        }
    }
}
```

#### Context Window (`ClaudeCodeDataSource.swift`)
```swift
private let defaultContextWindow = 200_000  // Technical limit
```

## Token Usage Calculations

### ccusage Context Percentage
```typescript
// Includes input + cache tokens, excludes output
const inputTokens = usage.input_tokens
    + (usage.cache_creation_input_tokens ?? 0)
    + (usage.cache_read_input_tokens ?? 0);

const percentage = Math.round((inputTokens / contextLimit) * 100);
// contextLimit = 200,000 from LiteLLM
```

### q-status-menubar Percentages

#### Context Usage (Session)
```swift
// Uses 200K context window
let contextWindow = 200_000
let percent = Double(contextTokens) / Double(contextWindow) * 100
```

#### Plan Usage (Monthly)
```swift
// Uses 220K for Max20 plan
let planLimit = plan.tokenLimit  // 220,000 for max20
let percent = Double(monthlyTokens) / Double(planLimit) * 100
```

## Visual Comparison

| Metric | ccusage | q-status-menubar |
|--------|---------|------------------|
| **Context Window** | 200K (LiteLLM) | 200K (hardcoded) |
| **Plan Limits** | Not tracked | 220K (Max20), 88K (Max5), 19K (Pro) |
| **Data Source** | Dynamic API | Static configuration |
| **Token Types in Context** | input + cache | input + cache + output |
| **Purpose** | Per-session limits | Both session & monthly limits |

## Why the Difference?

The tools serve different purposes:

### ccusage (200K only)
- **Focus**: Technical capabilities
- **Question**: "How much context can I use in this conversation?"
- **Answer**: 200K tokens (model's technical limit)

### q-status-menubar (200K + 220K)
- **Focus**: Both technical and billing
- **Questions**:
  - "How much context in this session?" → 200K
  - "How much can I use this month?" → 220K (Max20 plan)

## Color Coding Thresholds

### ccusage
```typescript
// Context usage colors
< 50%: Green
50-80%: Yellow
> 80%: Red
```

### q-status-menubar
```swift
// Similar thresholds
< 70%: Normal
70-85%: Warning
> 85%: Critical
```

## Key Findings

1. **No Discrepancy**: The 200K vs 220K difference is intentional
   - 200K = Technical context window (both tools agree)
   - 220K = Max20 subscription monthly limit (q-status-menubar only)

2. **ccusage is Model-Aware**: Dynamically fetches limits per model
3. **q-status-menubar is Plan-Aware**: Tracks subscription quotas
4. **Both Exclude Output Tokens** from context calculations

## Recommendations

1. **For ccusage**: Consider adding plan limit tracking for monthly quota monitoring
2. **For q-status-menubar**: Consider fetching dynamic model limits from LiteLLM
3. **User Education**: Clarify the difference between:
   - Context limits (200K per session)
   - Plan limits (220K per month for Max20)

## Conclusion

Both tools correctly implement their intended functionality:
- **ccusage**: Accurately reports 200K technical context limits from LiteLLM
- **q-status-menubar**: Correctly tracks both 200K context and 220K plan limits

The apparent "difference" is actually two different metrics serving different purposes, both implemented correctly for their use cases.