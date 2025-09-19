// ABOUTME: Factory for creating different data source implementations
// Supports switching between Amazon Q and Claude Code data sources

use super::{datasource::DataSource, database::QDatabase, claude_datasource::ClaudeCodeDataSource};
use crate::utils::error::{Result, QStatusError};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DataSourceType {
    AmazonQ,
    ClaudeCode,
}

impl DataSourceType {
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "amazon-q" | "amazonq" | "q" => Some(Self::AmazonQ),
            "claude-code" | "claudecode" | "claude" => Some(Self::ClaudeCode),
            _ => None,
        }
    }

    pub fn as_str(&self) -> &str {
        match self {
            Self::AmazonQ => "amazon-q",
            Self::ClaudeCode => "claude-code",
        }
    }

    pub fn display_name(&self) -> &str {
        match self {
            Self::AmazonQ => "Amazon Q",
            Self::ClaudeCode => "Claude Code",
        }
    }
}

impl std::fmt::Display for DataSourceType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.display_name())
    }
}

pub struct DataSourceFactory;

impl DataSourceFactory {
    /// Create a data source based on the specified type
    pub fn create(source_type: DataSourceType, _cost_per_1k: f64) -> Result<Box<dyn DataSource>> {
        match source_type {
            DataSourceType::AmazonQ => {
                let db = QDatabase::new()?;
                Ok(Box::new(db))
            }
            DataSourceType::ClaudeCode => {
                let ds = ClaudeCodeDataSource::new()?;
                Ok(Box::new(ds))
            }
        }
    }

    /// Try to create any available data source, preferring the specified type
    pub fn create_with_fallback(preferred: DataSourceType, cost_per_1k: f64) -> Result<(Box<dyn DataSource>, DataSourceType)> {
        // Try preferred source first
        if let Ok(source) = Self::create(preferred, cost_per_1k) {
            return Ok((source, preferred));
        }

        // Try the other source as fallback
        let fallback = match preferred {
            DataSourceType::AmazonQ => DataSourceType::ClaudeCode,
            DataSourceType::ClaudeCode => DataSourceType::AmazonQ,
        };

        if let Ok(source) = Self::create(fallback, cost_per_1k) {
            eprintln!("Note: {} not available, using {} instead", preferred, fallback);
            return Ok((source, fallback));
        }

        // If both fail, return the original error
        Err(QStatusError::Config("No data source available. Ensure either Amazon Q or Claude Code is installed and has been used.".to_string()))
    }
}