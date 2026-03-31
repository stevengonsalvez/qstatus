// ABOUTME: DataSource implementation for Codex CLI.
// Reads rate-limit data from ~/.codex/sessions/ JSONL files.
// Polls every 2 minutes (rate limits change per turn).

import Foundation

public actor CodexDataSource: DataSource {
    private var lastSession: CodexSessionData?
    private var lastFetchDate: Date = .distantPast
    private var dataVersionCounter: Int = 0
    private let sessionsDirectory: URL
    private let inactiveThreshold: TimeInterval  // seconds before session is "inactive"

    /// Display data updated after each successful fetch, consumed by the UI layer.
    public private(set) var latestDisplayData: CodexDisplayData?

    public init() {
        self.sessionsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        self.inactiveThreshold = 3600  // 1 hour
    }

    /// Visible initializer for testing with explicit sessions directory and threshold.
    public init(sessionsDirectory: URL, inactiveThreshold: TimeInterval = 3600) {
        self.sessionsDirectory = sessionsDirectory
        self.inactiveThreshold = inactiveThreshold
    }

    // MARK: - DataSource Protocol

    public func openIfNeeded() async throws {
        guard FileManager.default.fileExists(atPath: sessionsDirectory.path) else {
            throw CodexError.noSessionsDirectory
        }
        if lastSession == nil {
            try await refreshSession()
        }
    }

    public func dataVersion() async throws -> Int {
        if Date().timeIntervalSince(lastFetchDate) > 120 {  // 2 min refresh
            try await refreshSession()
        }
        return dataVersionCounter
    }

    public func fetchLatestUsage(window: TimeInterval?) async throws -> UsageSnapshot {
        if Date().timeIntervalSince(lastFetchDate) > 120 {
            try await refreshSession()
        }
        let usedPercent = Int(lastSession?.rateLimits?.primaryUsedPercent.rounded() ?? 0)
        return UsageSnapshot(
            timestamp: Date(),
            tokensUsed: usedPercent,
            messageCount: 0,
            conversationId: lastSession?.sessionId ?? "codex-session",
            sessionLimitOverride: 100)
    }

    public func fetchSessions(limit: Int, offset: Int, groupByFolder: Bool, activeOnly: Bool) async throws -> [SessionSummary] {
        []
    }

    public func fetchSessionDetail(key: String) async throws -> SessionDetails? {
        nil
    }

    public func sessionCount(activeOnly: Bool) async throws -> Int {
        0
    }

    public func fetchGlobalMetrics(limitForTop: Int) async throws -> GlobalMetrics {
        GlobalMetrics(totalSessions: 0, totalTokens: 0, sessionsNearLimit: 0, topHeavySessions: [])
    }

    public func fetchGlobalTotalsByModel() async throws -> [QDBReader.GlobalByModel] {
        []
    }

    public func fetchPeriodTokensByModel(now: Date) async throws -> [QDBReader.PeriodByModel] {
        []
    }

    public func fetchPeriodTokensByModel(forKeys keys: [String], now: Date) async throws -> [QDBReader.PeriodByModel] {
        []
    }

    public func fetchMonthlyMessageCount(now: Date) async throws -> Int {
        0
    }

    // MARK: - Session Refresh

    private func refreshSession() async throws {
        guard let fileURL = Self.findActiveSessionFile(in: sessionsDirectory) else {
            lastSession = nil
            latestDisplayData = nil
            lastFetchDate = Date()
            return
        }

        let sessionData = try Self.parseSessionFile(fileURL, inactiveThreshold: inactiveThreshold)
        lastSession = sessionData
        lastFetchDate = Date()
        dataVersionCounter += 1
        latestDisplayData = Self.makeDisplayData(from: sessionData)
    }

    // MARK: - Session File Discovery

    /// Find the most recently modified JSONL file in the sessions directory (modified within last 24h).
    public static func findActiveSessionFile(in directory: URL? = nil) -> URL? {
        let sessionsDir = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        let fm = FileManager.default

        guard fm.fileExists(atPath: sessionsDir.path) else { return nil }

        var bestFile: URL?
        var bestMtime: Date = .distantPast
        let cutoff = Date().addingTimeInterval(-86400)  // 24 hours ago

        guard let enumerator = fm.enumerator(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let mtime = values.contentModificationDate else { continue }
            guard mtime > cutoff else { continue }
            if mtime > bestMtime {
                bestMtime = mtime
                bestFile = fileURL
            }
        }

        return bestFile
    }

    // MARK: - JSONL Parsing

    /// Parse a JSONL session file for the latest rate_limits and session metadata.
    /// Stream-parses JSONL in reverse using a file handle, O(1) memory for the common case.
    /// Reads backwards in 16 KB chunks until all required fields are found or file exhausted.
    public static func parseSessionFile(_ url: URL, inactiveThreshold: TimeInterval = 3600) throws -> CodexSessionData {
        var rateLimits: CodexRateLimits?
        var cwd: String?
        var model: String?
        var sessionId: String?
        var turnSummary: String?

        // Reverse-chunk reader: read file backwards in 16 KB chunks, extract complete JSONL lines.
        let chunkSize: Int = 16_384
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let fileSize = Int((try? fileHandle.seekToEndOfFile()) ?? 0)
        var offset = fileSize
        var leftover = Data()   // partial line fragment from the right of the previous chunk

        outerLoop: while offset > 0 || !leftover.isEmpty {
            let readSize = min(chunkSize, offset)
            offset -= readSize

            var chunk: Data
            if readSize > 0 {
                try fileHandle.seek(toOffset: UInt64(offset))
                chunk = fileHandle.readData(ofLength: readSize)
            } else {
                chunk = Data()
            }

            // Prepend any leftover from the previous (right-side) chunk
            chunk.append(leftover)
            leftover = Data()

            // Split into lines; the first segment may be an incomplete line (save as leftover for next round)
            let newline = UInt8(ascii: "\n")
            var lineEnd = chunk.count
            var lines: [String] = []

            for i in stride(from: chunk.count - 1, through: 0, by: -1) {
                if chunk[i] == newline {
                    let lineData = chunk[(i + 1)..<lineEnd]
                    if !lineData.isEmpty, let s = String(data: lineData, encoding: .utf8), !s.trimmingCharacters(in: .whitespaces).isEmpty {
                        lines.append(s)
                    }
                    lineEnd = i
                }
            }
            // Remaining bytes at start of chunk are a partial line — carry over to next iteration
            if lineEnd > 0 {
                leftover = chunk[0..<lineEnd]
            }

            // If we've exhausted the file and still have leftover, process it now
            if offset == 0, !leftover.isEmpty, let s = String(data: leftover, encoding: .utf8), !s.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(s)
                leftover = Data()
            }

        // Parse each line extracted from this chunk
        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let eventType = json["type"] as? String

            // Extract rate_limits from event_msg (take first found = most recent)
            if rateLimits == nil, eventType == "event_msg",
               let rl = json["rate_limits"] as? [String: Any] {
                rateLimits = parseRateLimits(rl)
            }

            // Extract cwd from session_meta or turn_context
            if cwd == nil {
                if eventType == "session_meta", let c = json["cwd"] as? String {
                    cwd = c
                } else if eventType == "turn_context", let c = json["cwd"] as? String {
                    cwd = c
                }
            }

            // Extract model from turn_context
            if model == nil, eventType == "turn_context", let m = json["model"] as? String {
                model = m
            }

            // Extract session ID from session_meta
            if sessionId == nil, eventType == "session_meta", let sid = json["id"] as? String {
                sessionId = sid
            }

            // Extract turn summary from turn_context
            if turnSummary == nil, eventType == "turn_context", let s = json["summary"] as? String {
                turnSummary = s
            }

            // Early exit if we have everything
            if rateLimits != nil && cwd != nil && model != nil && sessionId != nil {
                break outerLoop
            }
        }   // end lines loop

        // Early exit outer chunk loop if all fields found
        if rateLimits != nil && cwd != nil && model != nil && sessionId != nil {
            break outerLoop
        }
        }   // end outerLoop

        // Determine activity based on file mtime
        let mtime: Date
        if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
           let modDate = values.contentModificationDate {
            mtime = modDate
        } else {
            mtime = Date()
        }
        let isActive = Date().timeIntervalSince(mtime) < inactiveThreshold

        return CodexSessionData(
            rateLimits: rateLimits,
            cwd: cwd,
            model: model,
            sessionId: sessionId,
            lastActivity: mtime,
            isActive: isActive
        )
    }

    // MARK: - Rate Limits Parsing

    private static func parseRateLimits(_ rl: [String: Any]) -> CodexRateLimits? {
        guard let primary = rl["primary"] as? [String: Any],
              let secondary = rl["secondary"] as? [String: Any] else {
            return nil
        }

        let primaryUsed = (primary["used_percent"] as? Double) ?? 0
        let primaryWindow = (primary["window_minutes"] as? Int) ?? 300
        let primaryResets: Date
        if let ts = primary["resets_at"] as? Double {
            primaryResets = Date(timeIntervalSince1970: ts)
        } else if let ts = primary["resets_at"] as? Int {
            primaryResets = Date(timeIntervalSince1970: Double(ts))
        } else {
            primaryResets = Date()
        }

        let secondaryUsed = (secondary["used_percent"] as? Double) ?? 0
        let secondaryWindow = (secondary["window_minutes"] as? Int) ?? 10080
        let secondaryResets: Date
        if let ts = secondary["resets_at"] as? Double {
            secondaryResets = Date(timeIntervalSince1970: ts)
        } else if let ts = secondary["resets_at"] as? Int {
            secondaryResets = Date(timeIntervalSince1970: Double(ts))
        } else {
            secondaryResets = Date()
        }

        let credits = rl["credits"] as? [String: Any]
        let hasCredits = (credits?["has_credits"] as? Bool) ?? false
        let unlimited = (credits?["unlimited"] as? Bool) ?? false
        let balance: Double?
        if hasCredits && !unlimited {
            balance = credits?["balance"] as? Double
        } else {
            balance = nil
        }

        let planType = (rl["plan_type"] as? String) ?? "unknown"

        return CodexRateLimits(
            primaryUsedPercent: primaryUsed,
            primaryWindowMinutes: primaryWindow,
            primaryResetsAt: primaryResets,
            secondaryUsedPercent: secondaryUsed,
            secondaryWindowMinutes: secondaryWindow,
            secondaryResetsAt: secondaryResets,
            creditsBalance: balance,
            creditsUnlimited: unlimited,
            planType: planType
        )
    }

    // MARK: - Display Mapping

    private static func makeDisplayData(from session: CodexSessionData) -> CodexDisplayData {
        let primary: CodexDisplayData.RateItem?
        let secondary: CodexDisplayData.RateItem?

        if let rl = session.rateLimits {
            primary = CodexDisplayData.RateItem(
                label: "Primary (\(formatWindow(rl.primaryWindowMinutes)))",
                usedPercent: rl.primaryUsedPercent,
                windowDescription: formatWindow(rl.primaryWindowMinutes),
                resetsAt: rl.primaryResetsAt
            )
            secondary = CodexDisplayData.RateItem(
                label: "Weekly (\(formatWindow(rl.secondaryWindowMinutes)))",
                usedPercent: rl.secondaryUsedPercent,
                windowDescription: formatWindow(rl.secondaryWindowMinutes),
                resetsAt: rl.secondaryResetsAt
            )
        } else {
            primary = nil
            secondary = nil
        }

        return CodexDisplayData(
            primary: session.rateLimits.map { _ in primary! },
            secondary: session.rateLimits.map { _ in secondary! },
            creditsBalance: session.rateLimits?.creditsBalance,
            creditsUnlimited: session.rateLimits?.creditsUnlimited ?? false,
            planType: session.rateLimits?.planType ?? "unknown",
            cwd: session.displayCwd,
            model: session.model,
            isActive: session.isActive,
            lastActivity: session.lastActivity,
            updatedAt: Date()
        )
    }

    private static func formatWindow(_ minutes: Int) -> String {
        if minutes >= 1440 {
            let days = minutes / 1440
            return "\(days)d"
        }
        let hours = minutes / 60
        return "\(hours)h"
    }

    /// Check if Codex sessions directory exists.
    public static func isAvailable() -> Bool {
        let sessionsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        return FileManager.default.fileExists(atPath: sessionsDir.path)
    }
}

public enum CodexError: Error, LocalizedError {
    case noSessionsDirectory
    case invalidFileEncoding
    case noSessionsFound

    public var errorDescription: String? {
        switch self {
        case .noSessionsDirectory: return "Codex sessions directory not found (~/.codex/sessions/)"
        case .invalidFileEncoding: return "Could not read JSONL file as UTF-8"
        case .noSessionsFound: return "No recent Codex sessions found"
        }
    }
}
