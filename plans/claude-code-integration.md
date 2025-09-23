# Claude Code Integration Implementation Plan

## Overview
Extend q-status-menubar (Swift) and q-status-cli (Rust) to monitor Claude Code usage in addition to Amazon Q, using ccusage as a reference implementation for JSONL parsing and cost calculation logic.

## Current State Analysis
Both q-status apps have clean architectures with clear separation between data reading, UI, and business logic. The key change is introducing a DataSource abstraction layer to support multiple AI coding assistants while maintaining all existing Amazon Q functionality.

## Desired End State
Users can switch between monitoring Amazon Q and Claude Code through configuration, with both apps displaying appropriate provider-specific metrics, cost calculations, and usage patterns.

### Key Discoveries:
- q-status-menubar uses actor-based concurrency with `QDBReader` at `Sources/Core/QDBReader.swift:22`
- q-status-cli uses trait-based architecture with `QDatabase` at `src/data/database.rs:141`
- ccusage JSONL parsing logic at `src/data-loader.ts:766-776`
- 5-hour billing block algorithm at `src/_session-blocks.ts:90-154`
- Cost calculation with cache discounts at `src/pricing-fetcher.ts:249-285`

## What We're NOT Doing
- Not modifying existing Amazon Q functionality
- Not changing UI layouts (only adding provider-specific fields)
- Not implementing real-time streaming (stick to polling model)
- Not supporting multiple providers simultaneously (single provider at a time)
- Not implementing Claude API calls (only local JSONL file reading)

## Implementation Approach
Create a protocol/trait-based abstraction that allows swapping data sources through configuration while keeping all UI and business logic unchanged. Port ccusage algorithms directly to Swift/Rust for consistency.

## Phase 1: DataSource Abstraction Foundation

### Overview
Create the core abstraction layer that allows multiple data source implementations without changing existing code structure.

### Changes Required:

#### 1. Swift - Create DataSource Protocol
**File**: `q-status-menubar/Sources/Core/DataSource.swift` (NEW)
**Changes**: Create protocol defining common interface

```swift
// ABOUTME: Protocol defining interface for all data source implementations
// Enables switching between Amazon Q, Claude Code, and other AI assistants

public protocol DataSource: Actor {
    func openIfNeeded() async throws
    func dataVersion() async throws -> Int
    func fetchLatestUsage(window: TimeInterval?) async throws -> UsageSnapshot
    func fetchSessions(limit: Int, offset: Int, groupByFolder: Bool, activeOnly: Bool) async throws -> [SessionSummary]
    func fetchSessionDetail(key: String) async throws -> SessionDetails?
    func fetchGlobalMetrics(limitForTop: Int) async throws -> GlobalMetrics
    func sessionCount(activeOnly: Bool) async throws -> Int
}
```

#### 2. Swift - Wrap Existing QDBReader
**File**: `q-status-menubar/Sources/Core/AmazonQDataSource.swift` (NEW)
**Changes**: Implement DataSource protocol for Amazon Q

```swift
// ABOUTME: Amazon Q implementation of DataSource protocol
// Wraps existing QDBReader to maintain backward compatibility

public actor AmazonQDataSource: DataSource {
    private let reader: QDBReader

    public init(config: QDBConfig = QDBConfig(), defaultContextWindow: Int = 175_000) {
        self.reader = QDBReader(config: config, defaultContextWindow: defaultContextWindow)
    }

    // Delegate all protocol methods to reader
}
```

#### 3. Swift - Update UpdateCoordinator
**File**: `q-status-menubar/Sources/Core/UpdateCoordinator.swift`
**Changes**: Replace direct QDBReader dependency with DataSource protocol

Line 4: Replace
```swift
public let reader: QDBReader
```
With:
```swift
public let dataSource: any DataSource
```

Line 26: Update initializer signature

#### 4. Rust - Create DataSource Trait
**File**: `q-status-cli/src/data/datasource.rs` (NEW)
**Changes**: Create trait defining common interface

```rust
// ABOUTME: Trait defining interface for all data source implementations
// Enables switching between Amazon Q, Claude Code, and other AI assistants

use crate::error::Result;

pub trait DataSource: Send + Sync {
    fn has_changed(&mut self) -> Result<bool>;
    fn get_current_conversation(&self, cwd: Option<&str>) -> Result<Option<QConversation>>;
    fn get_all_conversation_summaries(&self) -> Result<Vec<ConversationSummary>>;
    fn get_all_sessions(&self, cost_per_1k: f64) -> Result<Vec<Session>>;
    fn get_global_stats(&self) -> Result<GlobalStats>;
}
```

#### 5. Rust - Implement Trait for QDatabase
**File**: `q-status-cli/src/data/database.rs`
**Changes**: Add trait implementation at line 582

```rust
impl DataSource for QDatabase {
    // Move existing methods into trait implementation
}
```

#### 6. Rust - Update DataCollector
**File**: `q-status-cli/src/data/collector.rs`
**Changes**: Use trait object instead of concrete type

Line 16: Replace
```rust
database: QDatabase,
```
With:
```rust
database: Box<dyn DataSource>,
```

### Success Criteria:

#### Automated Verification:
- [ ] Swift: `swift build` succeeds
- [ ] Swift: `swift test` passes
- [ ] Rust: `cargo build` succeeds
- [ ] Rust: `cargo test` passes
- [ ] Rust: `cargo clippy` shows no warnings

#### Manual Verification:
- [ ] Both apps continue to work with Amazon Q data
- [ ] No UI changes visible yet
- [ ] No performance regression

---

## Phase 2: Claude Code Data Loading

### Overview
Implement JSONL file discovery, parsing, and session aggregation for Claude Code data.

### Changes Required:

#### 1. Swift - Claude Code Data Source
**File**: `q-status-menubar/Sources/Core/ClaudeCodeDataSource.swift` (NEW)
**Changes**: Implement DataSource protocol for Claude Code

```swift
// ABOUTME: Claude Code implementation of DataSource protocol
// Reads and parses JSONL files from ~/.claude/projects/

import Foundation

public actor ClaudeCodeDataSource: DataSource {
    private let claudePaths: [URL]
    private var lastDataVersion: Int = 0
    private var cachedSessions: [ClaudeSession] = []

    public init() {
        self.claudePaths = Self.discoverClaudePaths()
    }

    private static func discoverClaudePaths() -> [URL] {
        var paths: [URL] = []

        // Check environment variable first
        if let envPaths = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            // Parse comma-separated paths
        }

        // Default paths
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultPaths = [
            home.appendingPathComponent(".claude"),
            home.appendingPathComponent(".config/claude")
        ]

        // Check for projects subdirectory
        for path in defaultPaths {
            let projectsPath = path.appendingPathComponent("projects")
            if FileManager.default.fileExists(atPath: projectsPath.path) {
                paths.append(path)
            }
        }

        return paths
    }

    private func loadJSONLFiles() async throws -> [ClaudeUsageEntry] {
        // Glob for **/*.jsonl files
        // Parse each line as JSON
        // Validate with schema
        // Return parsed entries
    }
}
```

#### 2. Swift - JSONL Parser
**File**: `q-status-menubar/Sources/Core/ClaudeCodeParser.swift` (NEW)
**Changes**: Port ccusage parsing logic

```swift
// ABOUTME: JSONL parser for Claude Code usage data files
// Handles malformed entries gracefully and validates schema

struct ClaudeUsageEntry: Codable {
    let timestamp: Date
    let sessionId: String?
    let message: Message
    let costUSD: Double?

    struct Message: Codable {
        let usage: TokenUsage
        let model: String?
    }

    struct TokenUsage: Codable {
        let input_tokens: Int
        let output_tokens: Int
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
    }
}

func parseJSONLFile(at url: URL) -> [ClaudeUsageEntry] {
    // Read file line by line
    // Parse each line as JSON
    // Skip malformed entries
    // Return valid entries
}
```

#### 3. Rust - Claude Code Data Source
**File**: `q-status-cli/src/data/claude_datasource.rs` (NEW)
**Changes**: Implement DataSource trait for Claude Code

```rust
// ABOUTME: Claude Code implementation of DataSource trait
// Reads and parses JSONL files from ~/.claude/projects/

use std::path::{Path, PathBuf};
use serde::{Deserialize, Serialize};
use glob::glob;

pub struct ClaudeCodeDataSource {
    claude_paths: Vec<PathBuf>,
    last_data_version: u64,
    cached_sessions: Vec<ClaudeSession>,
}

impl ClaudeCodeDataSource {
    pub fn new() -> Result<Self> {
        let claude_paths = Self::discover_claude_paths()?;
        Ok(Self {
            claude_paths,
            last_data_version: 0,
            cached_sessions: Vec::new(),
        })
    }

    fn discover_claude_paths() -> Result<Vec<PathBuf>> {
        // Check CLAUDE_CONFIG_DIR environment variable
        // Check default paths: ~/.claude, ~/.config/claude
        // Verify projects subdirectory exists
    }

    fn load_jsonl_files(&self) -> Result<Vec<ClaudeUsageEntry>> {
        // Use glob crate to find **/*.jsonl
        // Parse each file line by line
        // Handle errors gracefully
    }
}

impl DataSource for ClaudeCodeDataSource {
    // Implement all trait methods
}
```

#### 4. Data Source Factory
**File**: `q-status-menubar/Sources/Core/DataSourceFactory.swift` (NEW)
**File**: `q-status-cli/src/data/factory.rs` (NEW)
**Changes**: Create factory for data source selection

### Success Criteria:

#### Automated Verification:
- [ ] Unit tests for JSONL parsing
- [ ] Unit tests for file discovery
- [ ] Integration tests with sample Claude data

#### Manual Verification:
- [ ] Can discover Claude directories
- [ ] Successfully parses JSONL files
- [ ] Handles malformed entries gracefully
- [ ] Memory efficient for large files

---

## Phase 3: Cost & Billing Logic

### Overview
Port ccusage's 5-hour billing blocks, cost calculation, and token aggregation algorithms.

### Changes Required:

#### 1. Session Block Algorithm
**File**: `q-status-menubar/Sources/Core/SessionBlockCalculator.swift` (NEW)
**File**: `q-status-cli/src/utils/session_blocks.rs` (NEW)
**Changes**: Port 5-hour billing period logic from `_session-blocks.ts:90-154`

```swift
// Swift version
struct SessionBlock {
    let id: String // ISO timestamp of block start
    let startTime: Date
    let endTime: Date // startTime + 5 hours
    let actualEndTime: Date? // Last activity
    let isActive: Bool
    let isGap: Bool
    let entries: [ClaudeUsageEntry]
    let tokenCounts: TokenCounts
    let costUSD: Double
    let models: [String]
}

func identifySessionBlocks(entries: [ClaudeUsageEntry], sessionDurationHours: Int = 5) -> [SessionBlock] {
    // Sort entries by timestamp
    // Group into 5-hour blocks
    // Detect gaps > 5 hours
    // Create gap blocks
    // Calculate costs per block
}
```

#### 2. Cost Calculator
**File**: `q-status-menubar/Sources/Core/ClaudeCostCalculator.swift` (NEW)
**File**: `q-status-cli/src/utils/cost_calculator.rs` (NEW)
**Changes**: Port pricing logic from `pricing-fetcher.ts:249-285`

```swift
enum CostMode {
    case display    // Use pre-calculated costUSD
    case calculate  // Always calculate from tokens
    case auto       // Use costUSD if available, else calculate
}

func calculateCost(tokens: TokenUsage, model: String, mode: CostMode) -> Double {
    // Apply model-specific pricing
    // Handle cache token discounts
    // Support all cost modes
}
```

#### 3. Model Pricing Data
**File**: `q-status-menubar/Resources/model_prices.json` (NEW)
**File**: `q-status-cli/resources/model_prices.json` (NEW)
**Changes**: Include LiteLLM pricing data or fetch dynamically

### Success Criteria:

#### Automated Verification:
- [ ] Unit tests for session block algorithm
- [ ] Unit tests for cost calculation
- [ ] Tests for edge cases (gaps, timezone handling)

#### Manual Verification:
- [ ] 5-hour blocks display correctly
- [ ] Gap detection works
- [ ] Costs match ccusage calculations
- [ ] Cache token discounts applied

---

## Phase 4: UI & Configuration

### Overview
Add provider switching UI and enhance displays with Claude-specific metrics.

### Changes Required:

#### 1. Settings Extension
**File**: `q-status-menubar/Sources/Core/Settings.swift`
**Changes**: Add data source configuration at line 35

```swift
@Published public var dataSourceType: DataSourceType = .amazonQ
@Published public var claudeConfigPaths: [String] = []
@Published public var costMode: CostMode = .auto
```

**File**: `q-status-cli/src/app/config.rs`
**Changes**: Add to Config struct

```rust
pub data_source: DataSourceType,
pub claude_config_paths: Vec<String>,
pub cost_mode: CostMode,
```

#### 2. Provider Switching UI
**File**: `q-status-menubar/Sources/App/Preferences/PreferencesWindow.swift`
**Changes**: Add provider selector

**File**: `q-status-cli/src/ui/dashboard.rs`
**Changes**: Add provider indicator and switching keybind

#### 3. Enhanced Metrics Display
- Model breakdown for Claude Code
- Cache efficiency metrics
- 5-hour billing block indicators
- Burn rate visualization

### Success Criteria:

#### Automated Verification:
- [ ] UI tests for provider switching
- [ ] Configuration persistence tests

#### Manual Verification:
- [ ] Can switch between providers via UI
- [ ] Settings persist across restarts
- [ ] Claude-specific metrics display
- [ ] No UI glitches or layout issues

---

## Phase 5: Testing & Documentation

### Overview
Comprehensive testing, performance optimization, and documentation.

### Changes Required:

#### 1. Test Data
**Directory**: `test-data/claude/` (NEW)
**Changes**: Sample JSONL files for testing

#### 2. Integration Tests
- End-to-end provider switching
- Large dataset performance
- Edge cases and error handling

#### 3. Documentation
- Update README with Claude Code support
- Configuration guide
- Troubleshooting section

### Success Criteria:

#### Automated Verification:
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] Performance benchmarks meet targets
- [ ] No memory leaks detected

#### Manual Verification:
- [ ] Works with real Claude Code data
- [ ] Performance acceptable with large datasets
- [ ] Documentation clear and complete
- [ ] Error messages helpful

---

## Testing Strategy

### Unit Tests:
- JSONL parsing with valid/invalid data
- Session block algorithm edge cases
- Cost calculation accuracy
- File discovery logic

### Integration Tests:
- Provider switching flow
- Data source factory
- Configuration persistence
- UI updates with different providers

### Manual Testing Steps:
1. Install apps with Claude Code support
2. Generate Claude Code usage data
3. Verify data appears in both apps
4. Switch between providers
5. Compare costs with ccusage
6. Test with large datasets (>1000 sessions)
7. Verify 5-hour blocks display correctly

## Performance Considerations
- Cache parsed JSONL data with file modification tracking
- Process files incrementally, not all at once
- Use concurrent file parsing where possible
- Implement data pagination for large datasets

## Migration Notes
- Existing Amazon Q functionality unchanged
- Settings migration automatic with defaults
- No data migration needed (different data sources)

## References
- Original research: `research/2025-09-15_claude-code-integration.md`
- ccusage implementation: `ccusage/src/`
- q-status-menubar: `q-status-menubar/Sources/Core/QDBReader.swift:22`
- q-status-cli: `q-status-cli/src/data/database.rs:141`