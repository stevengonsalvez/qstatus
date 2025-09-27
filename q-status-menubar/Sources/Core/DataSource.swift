// ABOUTME: Protocol that abstracts the data source interface for Q status data
// This enables swapping between QDBReader (SQLite) and future implementations like Claude Code integration

import Foundation

/// Protocol defining the interface for reading Q session data.
/// Implementations must be thread-safe actors to handle concurrent access.
///
/// This abstraction layer enables multiple data source implementations:
/// - QDBReader: Direct SQLite access to Amazon Q's database
/// - ClaudeCodeDataSource: Future integration with Claude Code's data
/// - MockDataSource: Testing and development
public protocol DataSource: Actor {

    // MARK: - Initialization

    /// Opens or initializes the data source connection if needed.
    /// Should be idempotent - safe to call multiple times.
    func openIfNeeded() async throws

    // MARK: - Change Detection

    /// Returns a version identifier that changes when underlying data changes.
    /// Used for efficient polling - only fetch new data when version changes.
    /// - Returns: Integer version number, 0 if unknown
    func dataVersion() async throws -> Int

    // MARK: - Current Usage

    /// Fetches the latest usage snapshot for the most recent session.
    /// - Parameter window: Optional time window for filtering (currently unused)
    /// - Returns: Usage snapshot with tokens, messages, and session info
    func fetchLatestUsage(window: TimeInterval?) async throws -> UsageSnapshot

    // MARK: - Session Management

    /// Fetches a list of sessions with pagination and filtering options.
    /// - Parameters:
    ///   - limit: Maximum number of sessions to return (default: 50)
    ///   - offset: Number of sessions to skip for pagination
    ///   - groupByFolder: If true, aggregate sessions by working directory
    ///   - activeOnly: If true, only return recently active sessions
    /// - Returns: Array of session summaries ordered by most recent first
    func fetchSessions(
        limit: Int,
        offset: Int,
        groupByFolder: Bool,
        activeOnly: Bool
    ) async throws -> [SessionSummary]

    /// Fetches detailed information about a specific session.
    /// - Parameter key: The session identifier (conversation key)
    /// - Returns: Detailed session info with token breakdown, or nil if not found
    func fetchSessionDetail(key: String) async throws -> SessionDetails?

    /// Returns the total count of sessions.
    /// - Parameter activeOnly: If true, only count recently active sessions
    /// - Returns: Total number of sessions
    func sessionCount(activeOnly: Bool) async throws -> Int

    // MARK: - Global Metrics

    /// Fetches global metrics across all sessions.
    /// - Parameter limitForTop: Number of top heavy sessions to include
    /// - Returns: Global metrics including totals and top sessions
    func fetchGlobalMetrics(limitForTop: Int) async throws -> GlobalMetrics

    // MARK: - Optional Extended Metrics

    /// Fetches global token totals grouped by model.
    /// Optional - implementations may return empty array if not supported.
    /// - Returns: Array of token/message counts per model
    func fetchGlobalTotalsByModel() async throws -> [QDBReader.GlobalByModel]

    /// Fetches token usage for all sessions for specific time periods grouped by model.
    /// Optional - implementations may return empty array if not supported.
    /// - Parameter now: Reference date for period calculations
    /// - Returns: Array of period metrics per model
    func fetchPeriodTokensByModel(now: Date) async throws -> [QDBReader.PeriodByModel]

    /// Fetches token usage for specific sessions for time periods grouped by model.
    /// Optional - implementations may return empty array if not supported.
    /// - Parameters:
    ///   - keys: Session keys to analyze
    ///   - now: Reference date for period calculations
    /// - Returns: Array of period metrics per model
    func fetchPeriodTokensByModel(
        forKeys keys: [String],
        now: Date
    ) async throws -> [QDBReader.PeriodByModel]

    /// Fetches monthly message count across all sessions.
    /// Optional - implementations may return 0 if not supported.
    /// - Parameter now: Reference date for the month
    /// - Returns: Total message count for the month
    func fetchMonthlyMessageCount(now: Date) async throws -> Int
}

// MARK: - Default Implementations

public extension DataSource {
    /// Default implementation for fetchLatestUsage without window parameter
    func fetchLatestUsage() async throws -> UsageSnapshot {
        try await fetchLatestUsage(window: nil)
    }

    /// Default implementation with standard pagination values
    func fetchSessions() async throws -> [SessionSummary] {
        try await fetchSessions(
            limit: 50,
            offset: 0,
            groupByFolder: false,
            activeOnly: false
        )
    }

    /// Default implementation for session count without filter
    func sessionCount() async throws -> Int {
        try await sessionCount(activeOnly: false)
    }

    /// Default implementation for global metrics with 5 top sessions
    func fetchGlobalMetrics() async throws -> GlobalMetrics {
        try await fetchGlobalMetrics(limitForTop: 5)
    }

    /// Default implementation for period tokens for all sessions using current date
    func fetchPeriodTokensByModel() async throws -> [QDBReader.PeriodByModel] {
        try await fetchPeriodTokensByModel(now: Date())
    }

    /// Default implementation for period tokens using current date
    func fetchPeriodTokensByModel(forKeys keys: [String]) async throws -> [QDBReader.PeriodByModel] {
        try await fetchPeriodTokensByModel(forKeys: keys, now: Date())
    }

    /// Default implementation for monthly messages using current date
    func fetchMonthlyMessageCount() async throws -> Int {
        try await fetchMonthlyMessageCount(now: Date())
    }

    /// Default empty implementation for optional methods
    func fetchGlobalTotalsByModel() async throws -> [QDBReader.GlobalByModel] {
        []
    }
}