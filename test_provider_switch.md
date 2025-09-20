# Provider Switching Test Plan

## Implementation Complete

The provider switching functionality has been successfully implemented with the following changes:

### Phase 3: Collector Restart Logic ✅
1. **Modified `collector.rs`**:
   - Added `spawn_collector_with_datasource()` method that accepts a `Box<dyn DataSource>` parameter
   - This allows spawning a collector with any data source implementation
   - Exported the new function in `mod.rs`

### Phase 4: State Management ✅
2. **Modified `state.rs`**:
   - Added `active_data_source: Arc<Mutex<DataSourceType>>` field for thread-safe tracking
   - Updated `get_active_data_source()` to read from the mutex
   - Updated `set_active_data_source()` to write to the mutex
   - Initialized the field in `new()` with the configured data source

3. **Modified `main.rs`**:
   - Wrapped collector handle in `Arc<Mutex<Option<JoinHandle>>>` for shared access
   - Updated `run_event_loop()` to accept the collector handle and event sender
   - Added provider switching logic in the key event handler:
     - Detects when `dashboard.is_switching_provider()` returns true
     - Toggles between Amazon Q and Claude Code providers
     - Aborts the current collector task
     - Creates a new data source using `DataSourceFactory`
     - Spawns a new collector with the new data source
     - Updates the app state with the new provider
     - Resets the switching flag

4. **Modified `dashboard.rs`**:
   - Added visual feedback in the header showing "[Switching...]" during provider switch
   - Status color changes to yellow while switching
   - The 'P' key handler already sets the `switching_provider` flag

## Testing Instructions

1. **Build the application**:
   ```bash
   cd /Users/stevengonsalvez/d/git/qlips/q-status-cli
   cargo build --release
   ```

2. **Run the application**:
   ```bash
   ./target/release/qstatus-cli
   ```

3. **Test provider switching**:
   - Press 'P' to switch between providers
   - Observe the header changes to show "[Switching...]" in yellow
   - Watch for the provider name to change between "Amazon Q" and "Claude Code"
   - Check the console for switching messages

4. **Verify functionality**:
   - Data should update from the new provider after switching
   - The app should remain responsive during the switch
   - No crashes or panics should occur
   - Rapid switching (pressing 'P' multiple times) should be handled gracefully

## Key Features Implemented

- ✅ Thread-safe provider tracking with Arc<Mutex>
- ✅ Clean collector task abortion before switching
- ✅ Visual feedback during switching operation
- ✅ Error handling for data source creation failures
- ✅ Console messages for debugging
- ✅ Support for toggling between Amazon Q and Claude Code
- ✅ Maintains app state consistency during switches

## Error Handling

The implementation includes robust error handling:
- If the new data source cannot be created, an error message is displayed
- If the new collector cannot be started, an error message is displayed
- The app continues running even if a switch fails
- The old collector is properly aborted before attempting to start a new one

## Thread Safety

All shared state is protected with appropriate synchronization:
- `active_data_source` uses Arc<Mutex> for safe concurrent access
- Collector handle is wrapped in Arc<Mutex> for sharing between threads
- State updates are atomic and consistent