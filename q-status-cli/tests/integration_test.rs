use q_status::{AppConfig, AppState};

#[test]
fn test_app_state_creation() {
    let config = AppConfig::default();
    let state = AppState::new(config);

    // Verify initial state
    let usage = state.token_usage.lock().unwrap();
    assert_eq!(usage.used, 0);
    assert_eq!(usage.limit, 175000);  // Updated to match actual Amazon Q context window
    assert_eq!(usage.percentage, 0.0);
}

#[test]
fn test_token_usage_update() {
    let config = AppConfig::default();
    let state = AppState::new(config);

    // Update token usage
    state.update_token_usage(1000);

    let usage = state.token_usage.lock().unwrap();
    assert_eq!(usage.used, 1000);
    assert!(usage.percentage > 0.0);
}

#[test]
fn test_config_defaults() {
    let config = AppConfig::default();
    assert_eq!(config.refresh_rate, 2);
    assert_eq!(config.token_limit, 44000);
    assert_eq!(config.warning_threshold, 70.0);
    assert_eq!(config.critical_threshold, 90.0);
}
