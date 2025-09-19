# Research: Extending q-status to Monitor Claude Code Usage

**Date**: 2025-09-15 17:30:00
**Repository**: qlips
**Branch**: feat/cc
**Research Type**: Comprehensive

## Research Question
How to extend q-status-menubar and q-status-cli to monitor Claude Code usage in addition to Amazon Q, using ccusage as a reference implementation.

## Executive Summary
The integration is highly feasible. Both q-status apps have clean architectures that can be extended with a data source abstraction layer. Claude Code monitoring can be implemented by reading JSONL files from `~/.config/claude/projects/` and `~/.claude/projects/`, similar to how ccusage works. The key is creating a protocol-based abstraction to support switching between Amazon Q (SQLite) and Claude Code (JSONL) data sources.

## Key Findings
- **q-status apps are well-architected** with clear separation between data reading, metrics calculation, and UI presentation
- **ccusage provides a complete reference** for Claude Code data parsing, cost calculation, and session aggregation
- **Data source abstraction is the key** - both Swift and Rust can implement a common interface for multiple LLM providers
- **Most ccusage logic can be ported** directly to Swift/Rust with minimal modifications

## Detailed Findings

### Codebase Analysis

#### q-status-menubar (Swift)
- **Core Reader**: `Sources/Core/QDBReader.swift` - Reads Amazon Q's SQLite database
- **Models**: `Sources/Core/Models.swift` - Data structures for usage tracking
- **UI**: `Sources/App/MenuBarController.swift` and `Sources/App/DropdownView.swift`
- **Settings**: `Sources/Core/Settings.swift` - Configuration management
- **Key Features**: Real-time monitoring, cost tracking, session state management

#### q-status-cli (Rust)
- **Database Layer**: `src/data/database.rs` - SQLite connection and queries
- **State Management**: `src/app/state.rs` - Thread-safe state with Arc<Mutex<T>>
- **UI**: `src/ui/dashboard.rs` - Ratatui-based terminal interface
- **Data Collection**: `src/data/collector.rs` - Background polling thread

#### ccusage (TypeScript)
- **Data Loading**: `src/data-loader.ts` - JSONL file discovery and parsing
- **Cost Calculation**: `src/calculate-cost.ts` - Token aggregation and pricing
- **Session Blocks**: `src/_session-blocks.ts` - 5-hour billing period grouping
- **Pricing**: `src/pricing-fetcher.ts` - LiteLLM integration for model pricing

### Claude Code Data Structure
**JSONL Location**: `~/.config/claude/projects/{project}/{session_id}/*.jsonl`

**Entry Format**:
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "sessionId": "session-123",
  "message": {
    "usage": {
      "input_tokens": 100,
      "output_tokens": 50,
      "cache_creation_input_tokens": 10,
      "cache_read_input_tokens": 20
    },
    "model": "claude-sonnet-4-20250514"
  },
  "costUSD": 0.01
}
```

### Architecture Insights
- **Pattern**: Data Source Protocol/Trait pattern for multi-provider support
- **Convention**: Configuration-driven provider selection
- **Design Decision**: Keep existing UI, abstract the data layer

## Code References
- `q-status-menubar/Sources/Core/QDBReader.swift:22` - Main data reader to abstract
- `q-status-menubar/Sources/Core/Models.swift:3-50` - Data models to extend
- `q-status-cli/src/data/database.rs:141` - Database struct to generalize
- `ccusage/src/data-loader.ts:77-139` - Claude path discovery logic
- `ccusage/src/_session-blocks.ts:90-154` - 5-hour billing block algorithm
- `ccusage/src/pricing-fetcher.ts:22-80` - LiteLLM pricing integration

## Implementation Design

### 1. Data Source Abstraction Layer

#### Swift Protocol
```swift
public protocol DataSource: Actor {
    func openIfNeeded() async throws
    func dataVersion() async throws -> Int
    func fetchLatestUsage(window: TimeInterval?) async throws -> UsageSnapshot
    func fetchSessions(limit: Int, offset: Int, groupByFolder: Bool, activeOnly: Bool) async throws -> [SessionSummary]
    func fetchGlobalMetrics(limitForTop: Int) async throws -> GlobalMetrics
}
```

#### Rust Trait
```rust
pub trait DataSource {
    type Config;
    type Error;

    fn new(config: Self::Config) -> Result<Self, Self::Error> where Self: Sized;
    fn has_changed(&mut self) -> Result<bool, Self::Error>;
    fn get_current_usage(&self) -> Result<Option<CurrentUsage>, Self::Error>;
    fn get_all_sessions(&self) -> Result<Vec<Session>, Self::Error>;
}
```

### 2. Claude Code Reader Implementation

#### Key Components
- **JSONL Parser**: Parse Claude usage entries with error resilience
- **Session Aggregator**: Group entries by session ID and calculate totals
- **Cost Calculator**: Apply model-specific pricing (from LiteLLM or config)
- **Cache Manager**: Cache parsed data with file modification time invalidation

#### Swift Implementation Approach
```swift
public actor ClaudeCodeReader: DataSource {
    private let config: ClaudeCodeConfig
    private var cachedData: ClaudeCodeSnapshot?

    func loadSessionsFromPath(_ projectsPath: URL) async throws -> [ClaudeCodeSession] {
        // 1. Glob for *.jsonl files
        // 2. Parse each file line by line
        // 3. Aggregate by session
        // 4. Calculate costs
    }
}
```

#### Rust Implementation Approach
```rust
pub struct ClaudeCodeDataSource {
    config: ClaudeCodeConfig,
    cached_sessions: Option<Vec<ClaudeSession>>,

    fn load_sessions(&self) -> Result<Vec<ClaudeSession>, Error> {
        // 1. Use glob crate for file discovery
        // 2. Parse with serde_json
        // 3. Group with HashMap
        // 4. Calculate costs
    }
}
```

### 3. UI Integration

#### Data Source Selector
- Add preference toggle: Amazon Q ↔ Claude Code
- Show provider-specific metrics (models, cache usage, etc.)
- Different cost displays (estimated vs actual)

#### Enhanced Display
- Model breakdown when using Claude Code
- 5-hour billing block indicators
- Cache token efficiency metrics
- Burn rate visualization

### 4. Reusable ccusage Components

#### Core Algorithms to Port
1. **Token Calculation**: `getTotalTokens()` - sum all token types
2. **Cost Calculation**: Multi-tier pricing with cache discounts
3. **Session Blocks**: 5-hour billing period grouping
4. **Burn Rate**: Tokens per minute with projections

#### Data Structures
- Token counts (4 types: input, output, cache creation, cache read)
- Model pricing maps from LiteLLM
- Session block aggregations with gap detection

#### Configuration Patterns
- Multiple Claude directory support
- Cost calculation modes (auto/calculate/display)
- Model-specific context windows

## Recommendations

### Phase 1: Foundation (Week 1)
1. Create `DataSource` protocol/trait in both apps
2. Implement basic `ClaudeCodeReader` with JSONL parsing
3. Add data source selector to preferences
4. Test with sample Claude Code data

### Phase 2: Feature Parity (Week 2)
1. Port ccusage aggregation logic
2. Implement cost calculation with LiteLLM pricing
3. Add model breakdowns to UI
4. Implement caching for performance

### Phase 3: Enhanced Features (Week 3)
1. Add 5-hour billing block visualization
2. Implement burn rate indicators
3. Add project-based filtering
4. Cache token efficiency metrics

### Testing Strategy
- Unit tests for JSONL parsing
- Integration tests with ccusage test data
- Performance tests for large datasets
- UI tests for source switching

## Open Questions
- Should we bundle ccusage as a subprocess or reimplement natively? (Recommend: native)
- How to handle LiteLLM pricing updates? (Recommend: periodic fetch with cache)
- Should settings sync between menubar and CLI? (Recommend: shared config file)

## References
- Internal docs: `/Users/stevengonsalvez/d/git/qlips/ccusage/CLAUDE.md`
- External resources: https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json
- Related research: ccusage documentation at https://github.com/ryoppippi/ccusage

## Implementation Notes

### Swift-Specific Considerations
- Use `Codable` for JSONL parsing
- `FileManager` for directory traversal
- `URLSession` for pricing API
- `@AppStorage` for preferences

### Rust-Specific Considerations
- Use `serde` for JSON parsing
- `glob` crate for file discovery
- `reqwest` for HTTP pricing
- `config` crate for settings

### Shared Concepts
- Unified data models across both implementations
- Common cost calculation logic
- Consistent UI patterns
- Shared configuration format

This research provides a complete roadmap for extending q-status to monitor Claude Code usage while maintaining the existing Amazon Q functionality.