// ABOUTME: Tests for ClaudeCodeDataSource implementation
// Verifies correct reading and parsing of Claude Code JSONL data

#[cfg(test)]
mod tests {
    use super::super::claude_datasource::ClaudeCodeDataSource;
    use super::super::datasource::DataSource;
    use tempfile::TempDir;
    use std::fs;

    fn create_test_jsonl_data() -> String {
        r#"{"timestamp":"2024-01-15T10:00:00Z","sessionId":"session-1","message":{"usage":{"input_tokens":100,"output_tokens":50},"model":"claude-3-5-sonnet-20241022","id":"msg-1"},"costUSD":0.001,"requestId":"req-1","cwd":"/test/project"}
{"timestamp":"2024-01-15T10:05:00Z","sessionId":"session-1","message":{"usage":{"input_tokens":200,"output_tokens":100,"cache_creation_input_tokens":50,"cache_read_input_tokens":25},"model":"claude-3-5-sonnet-20241022","id":"msg-2"},"costUSD":0.002,"requestId":"req-2","cwd":"/test/project"}
{"timestamp":"2024-01-15T11:00:00Z","sessionId":"session-2","message":{"usage":{"input_tokens":150,"output_tokens":75},"model":"claude-3-opus-20240229","id":"msg-3"},"costUSD":0.005,"requestId":"req-3","cwd":"/test/another"}
{"timestamp":"2024-01-15T11:00:00Z","sessionId":"session-2","message":{"usage":{"input_tokens":150,"output_tokens":75},"model":"claude-3-opus-20240229","id":"msg-3"},"costUSD":0.005,"requestId":"req-3","cwd":"/test/another"}"#.to_string()
    }

    #[tokio::test]
    async fn test_load_and_parse_jsonl() {
        // Create a temporary directory structure
        let temp_dir = TempDir::new().unwrap();
        let claude_dir = temp_dir.path().join("claude");
        let projects_dir = claude_dir.join("projects");
        let project_dir = projects_dir.join("test-project");

        fs::create_dir_all(&project_dir).unwrap();

        // Write test JSONL data
        let jsonl_file = project_dir.join("usage.jsonl");
        fs::write(&jsonl_file, create_test_jsonl_data()).unwrap();

        // Set environment variable to use our test directory
        std::env::set_var("CLAUDE_CONFIG_DIR", claude_dir.to_str().unwrap());

        // Create data source - this should load the data
        let result = ClaudeCodeDataSource::new();

        // Clean up environment variable
        std::env::remove_var("CLAUDE_CONFIG_DIR");

        // Check that it loaded successfully
        assert!(result.is_ok(), "Failed to create ClaudeCodeDataSource: {:?}", result.err());

        let data_source = result.unwrap();

        // Test getting conversation summaries
        let summaries = data_source.get_all_conversation_summaries().await.unwrap();
        assert_eq!(summaries.len(), 2, "Should have 2 sessions");

        // Test getting global stats
        let stats = data_source.get_global_stats(0.0).await.unwrap();
        assert_eq!(stats.total_conversations, 2);
        assert_eq!(stats.total_messages, 3); // 3 unique messages (one duplicate)

        // Test getting all sessions
        let sessions = data_source.get_all_sessions(0.0).await.unwrap();
        assert_eq!(sessions.len(), 2);

        // Verify session details
        let session1 = sessions.iter().find(|s| s.conversation_id == "session-1").unwrap();
        assert_eq!(session1.message_count, 2);
        assert_eq!(session1.directory, "/test/project");

        let session2 = sessions.iter().find(|s| s.conversation_id == "session-2").unwrap();
        assert_eq!(session2.message_count, 1); // Duplicate removed
        assert_eq!(session2.directory, "/test/another");
    }

    #[tokio::test]
    async fn test_cost_calculation() {
        let temp_dir = TempDir::new().unwrap();
        let claude_dir = temp_dir.path().join("claude");
        let projects_dir = claude_dir.join("projects");
        let project_dir = projects_dir.join("test-project");

        fs::create_dir_all(&project_dir).unwrap();

        // Create JSONL with entries that have no pre-calculated cost
        let jsonl_data = r#"{"timestamp":"2024-01-15T10:00:00Z","sessionId":"session-1","message":{"usage":{"input_tokens":1000000,"output_tokens":1000000},"model":"claude-3-5-sonnet-20241022","id":"msg-1"},"requestId":"req-1"}"#;

        let jsonl_file = project_dir.join("usage.jsonl");
        fs::write(&jsonl_file, jsonl_data).unwrap();

        std::env::set_var("CLAUDE_CONFIG_DIR", claude_dir.to_str().unwrap());

        let data_source = ClaudeCodeDataSource::new().unwrap();

        std::env::remove_var("CLAUDE_CONFIG_DIR");

        // Get session and check calculated cost
        let sessions = data_source.get_all_sessions(0.0).await.unwrap();
        assert_eq!(sessions.len(), 1);

        // For Sonnet: $3 per million input tokens, $15 per million output tokens
        // 1M input tokens = $3, 1M output tokens = $15, total = $18
        let session = &sessions[0];
        assert!((session.session_cost - 18.0).abs() < 0.01, "Cost should be approximately $18, got {}", session.session_cost);
    }

    #[tokio::test]
    async fn test_no_data_directory() {
        // Save current env var if exists
        let original_env = std::env::var("CLAUDE_CONFIG_DIR").ok();
        let original_home = std::env::var("HOME").ok();

        // Create a temp directory to use as a fake home
        let temp_dir = TempDir::new().unwrap();

        // Set HOME to temp directory so default paths won't exist
        std::env::set_var("HOME", temp_dir.path().to_str().unwrap());

        // Clear CLAUDE_CONFIG_DIR so it uses defaults
        std::env::remove_var("CLAUDE_CONFIG_DIR");

        let result = ClaudeCodeDataSource::new();

        // Restore original env vars
        if let Some(val) = original_env {
            std::env::set_var("CLAUDE_CONFIG_DIR", val);
        } else {
            std::env::remove_var("CLAUDE_CONFIG_DIR");
        }

        if let Some(val) = original_home {
            std::env::set_var("HOME", val);
        }

        assert!(result.is_err(), "Should fail when no Claude directories exist");
        if let Err(e) = result {
            assert!(e.to_string().contains("No valid Claude data directories found"));
        }
    }

    #[tokio::test]
    async fn test_deduplication() {
        let temp_dir = TempDir::new().unwrap();
        let claude_dir = temp_dir.path().join("claude");
        let projects_dir = claude_dir.join("projects");
        let project_dir = projects_dir.join("test-project");

        fs::create_dir_all(&project_dir).unwrap();

        // Create JSONL with duplicate entries (same request ID)
        let jsonl_data = r#"{"timestamp":"2024-01-15T10:00:00Z","sessionId":"session-1","message":{"usage":{"input_tokens":100,"output_tokens":50},"model":"claude-3-5-sonnet-20241022","id":"msg-1"},"requestId":"req-1"}
{"timestamp":"2024-01-15T10:00:00Z","sessionId":"session-1","message":{"usage":{"input_tokens":100,"output_tokens":50},"model":"claude-3-5-sonnet-20241022","id":"msg-1"},"requestId":"req-1"}
{"timestamp":"2024-01-15T10:01:00Z","sessionId":"session-1","message":{"usage":{"input_tokens":200,"output_tokens":100},"model":"claude-3-5-sonnet-20241022","id":"msg-2"},"requestId":"req-2"}"#;

        let jsonl_file = project_dir.join("usage.jsonl");
        fs::write(&jsonl_file, jsonl_data).unwrap();

        std::env::set_var("CLAUDE_CONFIG_DIR", claude_dir.to_str().unwrap());

        let data_source = ClaudeCodeDataSource::new().unwrap();

        std::env::remove_var("CLAUDE_CONFIG_DIR");

        let sessions = data_source.get_all_sessions(0.0).await.unwrap();
        assert_eq!(sessions.len(), 1);

        let session = &sessions[0];
        assert_eq!(session.message_count, 2, "Should have 2 messages after deduplication");
    }
}