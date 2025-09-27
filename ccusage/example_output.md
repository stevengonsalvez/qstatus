# Claude Code Token Usage - Expected Output

## Dashboard Active Session Display

When there's an active Claude Code session, the dashboard should now show:

### Active Session Panel
```
🔴 Active Session: abc12345 | Context: 45,234 tokens | Total: 128,456 tokens | $0.0234 (actual) | 42m ago
```

### Token Usage Gauge
Shows the **context tokens** (what's currently in Claude's memory):
```
Token Usage - 200K Limit 🟢
[████████████████████████░░░░░░░░░░░░░░░░░░░░░░░░]
45,234 / 200,000 tokens (22.6%)
```

### Session Details Panel
```
Session ID: abc12345-def6-7890-ghij-klmnopqrstuv

Token Breakdown (Current Context):
  Cache Read: 42,123 tokens
  Cache Creation: 3,111 tokens
  Total Context: 45,234 / 200,000 (22.6%)

Cumulative Usage (All Messages):
  Total Tokens: 128,456 (for billing)

Compaction Status:
  Safe - 94,766 tokens until warning

Messages: 42 exchanges
Avg per message: 1,077 tokens
```

## Key Differences

### Before (Previous Implementation)
- Only showed one token count that was ambiguous
- For active sessions, replaced total with context, losing cumulative information
- Users couldn't tell how many tokens they'd actually used for billing

### After (New Implementation)
- **Context Tokens**: What's currently in Claude's memory (affects whether compaction will occur)
- **Cumulative Tokens**: Total across all messages in the session (what you're billed for)
- Both values clearly labeled and displayed
- Progress bar shows context usage (the limiting factor for conversation length)
- Cumulative shown separately for billing awareness

## Why This Matters

1. **Context Window Management**: The context tokens show how close you are to hitting Claude's limit and triggering compaction
2. **Cost Tracking**: The cumulative tokens show your actual usage for billing purposes
3. **Clear Separation**: No more confusion about which number represents what

## Testing

To verify the implementation:
1. Start a Claude Code session
2. Send several messages
3. Check that:
   - Context tokens match the cache_read + cache_creation + input from the latest message
   - Cumulative tokens equal the sum of all tokens across all messages
   - The progress bar uses context tokens (not cumulative)
   - Both values are displayed in the active session panel