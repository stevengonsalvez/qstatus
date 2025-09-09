// ABOUTME: Centralized error handling for the application
// Provides consistent error types and conversions

use thiserror::Error;

#[derive(Error, Debug)]
pub enum QStatusError {
    #[error("Database error: {0}")]
    Database(#[from] rusqlite::Error),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("JSON parsing error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("Configuration error: {0}")]
    Config(String),

    #[error("Q database not found at any expected location")]
    DatabaseNotFound,

    #[error("File watching error: {0}")]
    FileWatch(#[from] notify::Error),

    #[error("Terminal error: {0}")]
    Terminal(String),

    #[error("Channel send error: {0}")]
    ChannelSend(String),
}

impl<T> From<crossbeam_channel::SendError<T>> for QStatusError {
    fn from(err: crossbeam_channel::SendError<T>) -> Self {
        QStatusError::ChannelSend(err.to_string())
    }
}

pub type Result<T> = std::result::Result<T, QStatusError>;
