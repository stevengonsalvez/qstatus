# Weekly Reports

Weekly reports aggregate your Claude Code usage by week, providing a mid-range view between daily and monthly reports. This helps identify weekly patterns and trends in your usage.

## Basic Usage

Show all weekly usage:

```bash
ccusage weekly
```

## Example Output

```
┌────────────────┬──────────────────┬────────┬─────────┬─────────────┬────────────┬──────────────┬────────────┐
│ Week           │ Models           │ Input  │ Output  │ Cache Create│ Cache Read │ Total Tokens │ Cost (USD) │
├────────────────┼──────────────────┼────────┼─────────┼─────────────┼────────────┼──────────────┼────────────┤
│ 2025-06-16     │ • opus-4         │  1,234 │ 156,789 │       2,048 │      4,096 │      164,167 │     $87.56 │
│                │ • sonnet-4       │        │         │             │            │              │            │
├────────────────┼──────────────────┼────────┼─────────┼─────────────┼────────────┼──────────────┼────────────┤
│ 2025-06-23     │ • sonnet-4       │  2,456 │ 234,567 │       3,072 │      6,144 │      246,239 │    $104.33 │
├────────────────┼──────────────────┼────────┼─────────┼─────────────┼────────────┼──────────────┼────────────┤
│ 2025-06-30     │ • opus-4         │  3,789 │ 345,678 │       4,096 │      8,192 │      361,755 │    $156.78 │
│                │ • sonnet-4       │        │         │             │            │              │            │
└────────────────┴──────────────────┴────────┴─────────┴─────────────┴────────────┴──────────────┴────────────┘
```

## Understanding the Columns

The columns are identical to daily reports but aggregated by week:

- **Week**: Start date of the week (configurable)
- **Models**: All Claude models used during the week
- **Input/Output**: Total tokens for the week
- **Cache Create/Read**: Cache token usage
- **Total Tokens**: Sum of all token types
- **Cost (USD)**: Estimated cost for the week

## Command Options

### Week Start Day

Configure which day starts the week:

```bash
# Start week on Sunday (default)
ccusage weekly --start-of-week sunday

# Start week on Monday
ccusage weekly --start-of-week monday
ccusage weekly -w monday

# Other options: tuesday, wednesday, thursday, friday, saturday
```

### Date Filtering

Filter by date range:

```bash
# Show specific period
ccusage weekly --since 20250601 --until 20250630

# Show last 4 weeks
ccusage weekly --since 20250501
```

### Sort Order

Control the order of weeks:

```bash
# Newest weeks first (default)
ccusage weekly --order desc

# Oldest weeks first
ccusage weekly --order asc
```

### Model Breakdown

See per-model weekly costs:

```bash
ccusage weekly --breakdown
```

```
┌────────────────┬──────────────────┬────────┬─────────┬────────────┐
│ Week           │ Models           │ Input  │ Output  │ Cost (USD) │
├────────────────┼──────────────────┼────────┼─────────┼────────────┤
│ 2025-06-16     │ opus-4, sonnet-4 │  1,234 │ 156,789 │     $87.56 │
├────────────────┼──────────────────┼────────┼─────────┼────────────┤
│   └─ opus-4    │                  │    800 │  80,000 │     $54.80 │
├────────────────┼──────────────────┼────────┼─────────┼────────────┤
│   └─ sonnet-4  │                  │    434 │  76,789 │     $32.76 │
└────────────────┴──────────────────┴────────┴─────────┴────────────┘
```

### JSON Output

Export weekly data as JSON:

```bash
ccusage weekly --json
```

```json
{
  "weekly": [
    {
      "week": "2025-06-16",
      "inputTokens": 1234,
      "outputTokens": 156789,
      "cacheCreationTokens": 2048,
      "cacheReadTokens": 4096,
      "totalTokens": 164167,
      "totalCost": 87.56,
      "modelsUsed": ["claude-opus-4-20250514", "claude-sonnet-4-20250514"],
      "modelBreakdowns": {
        "claude-opus-4-20250514": {
          "inputTokens": 800,
          "outputTokens": 80000,
          "totalCost": 54.80
        },
        "claude-sonnet-4-20250514": {
          "inputTokens": 434,
          "outputTokens": 76789,
          "totalCost": 32.76
        }
      }
    }
  ],
  "totals": {
    "inputTokens": 7479,
    "outputTokens": 737034,
    "cacheCreationTokens": 9216,
    "cacheReadTokens": 18432,
    "totalTokens": 772161,
    "totalCost": 348.67
  }
}
```

### Project Analysis

Group weekly usage by project:

```bash
# Show weekly usage per project
ccusage weekly --instances

# Filter to specific project
ccusage weekly --project my-project
```

### Cost Calculation Modes

Control cost calculation:

```bash
# Auto mode (default)
ccusage weekly --mode auto

# Always calculate from tokens
ccusage weekly --mode calculate

# Only use pre-calculated costs
ccusage weekly --mode display
```

### Offline Mode

Use cached pricing data:

```bash
ccusage weekly --offline
```

## Common Use Cases

### Weekly Trends

```bash
# See usage trends over past months
ccusage weekly --since 20250401
```

### Sprint Analysis

```bash
# Track usage during 2-week sprints (Monday start)
ccusage weekly --start-of-week monday --since 20250601
```

### Budget Planning

```bash
# Export for weekly budget tracking
ccusage weekly --json > weekly-budget.json
```

### Compare Workweeks

```bash
# Monday-Friday work pattern analysis
ccusage weekly --start-of-week monday --breakdown
```

### Team Reporting

```bash
# Weekly team usage report
ccusage weekly --instances --start-of-week monday
```

## Tips

1. **Week Start**: Choose a start day that aligns with your work schedule
2. **Breakdown View**: Use `--breakdown` to identify which models drive costs
3. **JSON Export**: Weekly JSON data is perfect for creating trend charts
4. **Project Tracking**: Use `--instances` to track project-specific weekly usage

## Related Commands

- [Daily Reports](/guide/daily-reports) - Day-by-day analysis
- [Monthly Reports](/guide/monthly-reports) - Monthly aggregates
- [Session Reports](/guide/session-reports) - Per-conversation analysis
- [Blocks Reports](/guide/blocks-reports) - 5-hour billing windows