# In-Menu Provider Switching Implementation Plan

## Overview
Add the ability to switch between Amazon Q and Claude Code data sources directly from the menu/UI in both q-status-menubar and q-status-cli without requiring application restart.

## Current State Analysis
Both applications currently support provider switching but require different levels of intervention:
- **Swift menubar**: Requires app restart after changing provider in preferences
- **Rust CLI**: Requires app restart or command-line argument to change provider

Both have the infrastructure for multiple providers but lack live switching capability.

## Desired End State
Users can switch between Amazon Q and Claude Code instantly from:
- **Swift**: Dropdown menu with provider selector
- **Rust**: 'P' key toggles between providers with immediate effect

### Key Discoveries:
- UpdateCoordinator holds immutable data source reference at `q-status-menubar/Sources/Core/UpdateCoordinator.swift:4`
- DataCollector runs in infinite loop at `q-status-cli/src/data/collector.rs:47`
- Provider switching keybind already defined at `q-status-cli/src/ui/dashboard.rs:1108`
- Factory pattern already implemented in both apps

## What We're NOT Doing
- Not changing the existing preferences UI (keep as backup method)
- Not persisting provider choice automatically (user must explicitly save)
- Not supporting simultaneous multiple providers (one at a time)
- Not adding complex provider management UI

## Implementation Approach
Make data source references mutable/replaceable and add coordinator restart logic to enable live switching without full app restart.

## Phase 1: Swift - Make UpdateCoordinator Restartable

### Overview
Modify UpdateCoordinator to support stopping and restarting with a different data source.

### Changes Required:

#### 1. Add Restart Capability to UpdateCoordinator
**File**: `q-status-menubar/Sources/Core/UpdateCoordinator.swift`
**Changes**: Add stop/restart methods and make data source replaceable

```swift
// Add new property for managing lifecycle
private var isRunning = false
private var pollingTask: Task<Void, Never>?

// Modify existing start() method to track task
public func start() {
    guard !isRunning else { return }
    isRunning = true

    pollingTask = Task { [weak self] in
        while !Task.isCancelled {
            guard let self = self else { break }
            // ... existing polling logic
            try? await Task.sleep(for: .seconds(self.settings.updateInterval))
        }
    }
}

// Add new stop method
public func stop() {
    isRunning = false
    pollingTask?.cancel()
    pollingTask = nil
}

// Add restart with new data source
public func restart(with newDataSource: any DataSource) async {
    stop()
    self.dataSource = newDataSource  // Need to make this var instead of let
    start()
}
```

#### 2. Update MenuBarController for Provider Switching
**File**: `q-status-menubar/Sources/App/MenuBarController.swift`
**Changes**: Add logic to restart coordinator with new provider

```swift
// Add method to handle provider change
@MainActor
func switchProvider(to newType: DataSourceType) async {
    // Stop current coordinator
    coordinator.stop()

    // Create new data source
    let newDataSource = DataSourceFactory.create(type: newType, settings: settings)

    // Restart coordinator with new data source
    await coordinator.restart(with: newDataSource)

    // Update settings
    settings.dataSourceType = newType
}
```

### Success Criteria:

#### Automated Verification:
- [ ] Swift build succeeds: `swift build`
- [ ] Tests pass: `swift test`
- [ ] No memory leaks when switching providers

#### Manual Verification:
- [ ] UpdateCoordinator stops cleanly
- [ ] New data source loads correctly
- [ ] UI updates reflect new provider data

---

## Phase 2: Swift - Add Provider Selector to Dropdown Menu

### Overview
Add a segmented control or menu items to the dropdown for provider selection.

### Changes Required:

#### 1. Add Provider Selector UI
**File**: `q-status-menubar/Sources/App/DropdownView.swift`
**Changes**: Add provider selector above bottom buttons (around line 247)

```swift
// Add before the bottom buttons HStack
Divider()

HStack {
    Text("Provider:")
        .font(.caption)
        .foregroundStyle(.secondary)

    Picker("", selection: Binding(
        get: { viewModel.settings?.dataSourceType ?? .amazonQ },
        set: { newValue in
            Task {
                await viewModel.switchProvider(to: newValue)
            }
        }
    )) {
        ForEach(DataSourceType.allCases, id: \.self) { type in
            Label(type.displayName, systemImage: type.iconName)
                .tag(type)
        }
    }
    .pickerStyle(.segmented)
    .frame(width: 200)
}
.padding(.horizontal)
```

#### 2. Add Switch Provider Method to ViewModel
**File**: `q-status-menubar/Sources/App/UsageViewModel.swift`
**Changes**: Add method to coordinate provider switching

```swift
@MainActor
func switchProvider(to newType: DataSourceType) async {
    // Show loading state
    self.isLoading = true

    // Delegate to MenuBarController
    if let controller = self.menuBarController {
        await controller.switchProvider(to: newType)
    }

    // Update loading state
    self.isLoading = false
}
```

### Success Criteria:

#### Automated Verification:
- [ ] UI renders correctly with picker
- [ ] Provider changes trigger coordinator restart

#### Manual Verification:
- [ ] Picker shows current provider
- [ ] Switching providers updates data immediately
- [ ] Loading state shows during switch
- [ ] No UI glitches during transition

---

## Phase 3: Rust - Implement Collector Restart Logic

### Overview
Enable the DataCollector to be stopped and restarted with a different data source.

### Changes Required:

#### 1. Make Collector Handle Accessible
**File**: `q-status-cli/src/main.rs`
**Changes**: Store collector handle in Arc<Mutex> for access from event loop

```rust
// Around line 84, wrap collector handle
let collector_handle = Arc::new(Mutex::new(Some(collector_handle)));
let collector_handle_clone = Arc::clone(&collector_handle);

// Pass to event loop
if let Err(e) = run_event_loop(
    &mut terminal,
    app_state.clone(),
    event_rx,
    event_tx.clone(),
    collector_handle_clone,
    config.clone(),
).await {
    // ... error handling
}
```

#### 2. Update Event Loop for Provider Switching
**File**: `q-status-cli/src/main.rs`
**Changes**: Add collector restart logic in event loop

```rust
// In run_event_loop function, after dashboard.handle_key()
if dashboard.is_switching_provider() {
    dashboard.reset_switching_flag();

    // Get current provider and toggle
    let current = app_state.get_active_data_source();
    let new_type = match current {
        DataSourceType::AmazonQ => DataSourceType::ClaudeCode,
        DataSourceType::ClaudeCode => DataSourceType::AmazonQ,
    };

    // Stop current collector
    if let Some(handle) = collector_handle.lock().unwrap().take() {
        handle.abort();
    }

    // Create new data source
    match DataSourceFactory::create(new_type, config.cost_per_1k_tokens) {
        Ok(new_datasource) => {
            // Spawn new collector
            let new_handle = DataCollector::spawn_with_datasource(
                app_state.clone(),
                event_tx.clone(),
                new_datasource,
                Duration::from_secs(config.update_interval),
            )?;

            // Store new handle
            *collector_handle.lock().unwrap() = Some(new_handle);

            // Update state
            app_state.set_active_data_source(new_type);
        }
        Err(e) => {
            // Show error in UI
            dashboard.show_error(&format!("Failed to switch provider: {}", e));
        }
    }
}
```

#### 3. Add Spawn Method with DataSource Parameter
**File**: `q-status-cli/src/data/collector.rs`
**Changes**: Add new spawn method that accepts data source

```rust
pub fn spawn_with_datasource(
    state: Arc<AppState>,
    event_tx: Sender<AppEvent>,
    datasource: Box<dyn DataSource>,
    update_interval: Duration,
) -> Result<tokio::task::JoinHandle<()>> {
    let collector = DataCollector::new(state, datasource, event_tx)?;

    Ok(tokio::spawn(async move {
        collector.run_with_interval(update_interval).await;
    }))
}
```

### Success Criteria:

#### Automated Verification:
- [ ] Cargo build succeeds: `cargo build`
- [ ] Tests pass: `cargo test`
- [ ] Clippy passes: `cargo clippy`

#### Manual Verification:
- [ ] 'P' key switches providers
- [ ] Data updates after switch
- [ ] No panic when switching
- [ ] Previous collector stops cleanly

---

## Phase 4: Rust - Update State Management

### Overview
Make AppState support mutable provider configuration.

### Changes Required:

#### 1. Update AppState for Mutable Provider
**File**: `q-status-cli/src/app/state.rs`
**Changes**: Add mutable provider field

```rust
pub struct AppState {
    // ... existing fields
    active_data_source: Arc<Mutex<DataSourceType>>,
}

impl AppState {
    pub fn get_active_data_source(&self) -> DataSourceType {
        *self.active_data_source.lock().unwrap()
    }

    pub fn set_active_data_source(&self, source: DataSourceType) {
        *self.active_data_source.lock().unwrap() = source;
    }
}
```

#### 2. Update Dashboard Display
**File**: `q-status-cli/src/ui/dashboard.rs`
**Changes**: Add visual feedback during switching

```rust
// In render_header, show switching state
if self.switching_provider {
    spans.push(Span::styled(
        " [Switching...]",
        Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD),
    ));
}
```

### Success Criteria:

#### Automated Verification:
- [ ] State updates correctly
- [ ] Provider persists in state

#### Manual Verification:
- [ ] Header shows correct provider
- [ ] Switching indicator appears
- [ ] State consistent after switch

---

## Phase 5: Testing & Polish

### Overview
Add comprehensive tests and polish the user experience.

### Changes Required:

#### 1. Swift Tests
**File**: `q-status-menubar/Tests/CoreTests/ProviderSwitchingTests.swift` (NEW)
```swift
class ProviderSwitchingTests: XCTestCase {
    func testCoordinatorRestart() async
    func testProviderSelectorUI()
    func testDataSourceFactorySwitch()
}
```

#### 2. Rust Tests
**File**: `q-status-cli/src/tests/provider_switching_test.rs` (NEW)
```rust
#[cfg(test)]
mod tests {
    #[tokio::test]
    async fn test_collector_restart()
    #[test]
    fn test_state_provider_switching()
}
```

### Success Criteria:

#### Automated Verification:
- [ ] All new tests pass
- [ ] No regression in existing tests
- [ ] Memory usage stable during switches

#### Manual Verification:
- [ ] Swift: Smooth transition between providers
- [ ] Rust: 'P' key provides instant feedback
- [ ] Both: Data refreshes correctly
- [ ] Both: Error handling works

---

## Testing Strategy

### Unit Tests:
- Coordinator restart logic
- State management for provider switching
- Factory creation with different types

### Integration Tests:
- End-to-end provider switching
- Data consistency after switch
- UI updates correctly

### Manual Testing Steps:
1. Start app with Amazon Q
2. Verify Amazon Q data loads
3. Switch to Claude Code via menu/key
4. Verify Claude Code data loads
5. Switch back to Amazon Q
6. Verify data updates correctly
7. Test rapid switching (stress test)
8. Test switching with no data available

## Performance Considerations
- Minimize UI freeze during switch (use async)
- Cancel pending requests when switching
- Clear caches appropriately
- Avoid memory leaks from abandoned tasks

## Migration Notes
- Existing preferences still work
- Command-line arguments still supported
- Environment variables still override

## References
- Current implementation research: This document
- DataSource abstraction: `plans/claude-code-integration.md`
- Swift UI: `q-status-menubar/Sources/App/DropdownView.swift:247`
- Rust keybinds: `q-status-cli/src/ui/dashboard.rs:1108`