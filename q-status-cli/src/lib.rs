// ABOUTME: Main library module that exports the public API
// Central module for the Q-Status Monitor application

pub mod app;
pub mod data;
pub mod ui;
pub mod utils;

// Re-export commonly used types
pub use app::{AppConfig, AppEvent, AppState, CostAnalysis, TokenUsage};
pub use utils::{QStatusError, Result};
