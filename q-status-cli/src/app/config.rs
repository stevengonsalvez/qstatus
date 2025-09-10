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
    #[serde(skip)]
    pub config_path: Option<PathBuf>,
    #[serde(skip)]
    pub debug: bool,
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
            config_path: None,
            debug: false,
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
