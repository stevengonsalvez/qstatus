// ABOUTME: Application configuration with defaults and file loading
// Supports TOML configuration files and environment variables

use directories::ProjectDirs;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    pub refresh_rate: u64,
    pub token_limit: u64,
    pub warning_threshold: f64,
    pub critical_threshold: f64,
    pub cost_per_1k_tokens: f64,
    pub history_retention_hours: u64,
    pub export_format: ExportFormat,
    pub theme: Theme,
    #[serde(default = "default_data_source")]
    pub data_source: String,
    #[serde(default = "default_cost_mode")]
    pub cost_mode: String,
    #[serde(default)]
    pub claude_config_paths: Vec<String>,
    #[serde(default = "default_claude_token_limit")]
    pub claude_token_limit: usize,
    #[serde(default = "default_claude_warning_threshold")]
    pub claude_warning_threshold: f64,
    #[serde(skip)]
    pub config_path: Option<PathBuf>,
    #[serde(skip)]
    pub debug: bool,
    #[serde(skip)]
    pub active_data_source: Option<crate::data::DataSourceType>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ExportFormat {
    Json,
    Csv,
    Markdown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Theme {
    Dark,
    Light,
    Auto,
}

fn default_data_source() -> String {
    "amazon-q".to_string()
}

fn default_cost_mode() -> String {
    "auto".to_string()
}

fn default_claude_token_limit() -> usize {
    200_000
}

fn default_claude_warning_threshold() -> f64 {
    0.8
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            refresh_rate: 2,
            token_limit: 44000,
            warning_threshold: 70.0,
            critical_threshold: 90.0,
            cost_per_1k_tokens: 0.0066,  // Claude 3.5 Sonnet (Oct 2024) blended rate ~30% output
            history_retention_hours: 24,
            export_format: ExportFormat::Csv,
            theme: Theme::Dark,
            data_source: default_data_source(),
            cost_mode: default_cost_mode(),
            claude_config_paths: vec![],
            claude_token_limit: default_claude_token_limit(),
            claude_warning_threshold: default_claude_warning_threshold(),
            config_path: None,
            debug: false,
            active_data_source: None,
        }
    }
}

impl AppConfig {
    pub fn load() -> Self {
        let mut config = Self::default();

        // Try to load from default location
        if let Some(proj_dirs) = ProjectDirs::from("com", "q-status", "q-status") {
            let config_path = proj_dirs.config_dir().join("config.toml");
            if config_path.exists() {
                if let Ok(contents) = std::fs::read_to_string(&config_path) {
                    if let Ok(file_config) = toml::from_str::<Self>(&contents) {
                        config = file_config;
                        config.config_path = Some(config_path);
                    }
                }
            }
        }

        // Override with environment variables
        if let Ok(rate) = std::env::var("Q_STATUS_REFRESH_RATE") {
            if let Ok(parsed) = rate.parse() {
                config.refresh_rate = parsed;
            }
        }

        // Check for data source environment variable
        if let Ok(source) = std::env::var("QSTATUS_DATA_SOURCE") {
            config.data_source = source;
        }

        // Check for cost mode environment variable
        if let Ok(mode) = std::env::var("QSTATUS_COST_MODE") {
            config.cost_mode = mode;
        }

        // Check for Claude token limit
        if let Ok(limit) = std::env::var("QSTATUS_CLAUDE_TOKEN_LIMIT") {
            if let Ok(parsed) = limit.parse() {
                config.claude_token_limit = parsed;
            }
        }

        // Check for Claude warning threshold
        if let Ok(threshold) = std::env::var("QSTATUS_CLAUDE_WARNING_THRESHOLD") {
            if let Ok(parsed) = threshold.parse() {
                config.claude_warning_threshold = parsed;
            }
        }

        config
    }

    pub fn save(&self) -> Result<(), Box<dyn std::error::Error>> {
        if let Some(proj_dirs) = ProjectDirs::from("com", "q-status", "q-status") {
            let config_dir = proj_dirs.config_dir();
            std::fs::create_dir_all(config_dir)?;

            let config_path = config_dir.join("config.toml");
            let contents = toml::to_string_pretty(self)?;
            std::fs::write(config_path, contents)?;
        }

        Ok(())
    }
}
