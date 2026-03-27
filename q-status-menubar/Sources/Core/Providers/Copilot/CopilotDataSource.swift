// ABOUTME: DataSource implementation for GitHub Copilot Enterprise.
// Reads quota data from the copilot_internal API, auth via gh CLI token or Keychain.
// Polls every 5 minutes (quota data is slow-moving).

import Foundation
import Security
#if canImport(Yams)
import Yams
#endif

public actor CopilotDataSource: DataSource {
    private let fetcher: CopilotUsageFetcher
    private var lastResponse: CopilotUsageResponse?
    private var lastFetchDate: Date = .distantPast
    private var dataVersionCounter: Int = 0
    private let hasToken: Bool

    /// Display data updated after each successful fetch, consumed by the UI layer.
    public private(set) var latestQuotaDisplay: CopilotQuotaDisplayData?

    public init() {
        let token = CopilotDataSource.resolveToken()
        self.hasToken = token != nil
        self.fetcher = CopilotUsageFetcher(oauthToken: token ?? "")
    }

    /// Visible initializer for testing with an explicit token.
    public init(token: String) {
        self.hasToken = !token.isEmpty
        self.fetcher = CopilotUsageFetcher(oauthToken: token)
    }

    // MARK: - DataSource Protocol

    public func openIfNeeded() async throws {
        guard hasToken else { throw CopilotAuthError.noTokenFound }
        if lastResponse == nil {
            try await refreshQuota()
        }
    }

    public func dataVersion() async throws -> Int {
        // Re-fetch if stale (> 5 minutes)
        if Date().timeIntervalSince(lastFetchDate) > 300 {
            try await refreshQuota()
        }
        return dataVersionCounter
    }

    public func fetchLatestUsage(window: TimeInterval?) async throws -> UsageSnapshot {
        if Date().timeIntervalSince(lastFetchDate) > 300 {
            try await refreshQuota()
        }
        guard let response = lastResponse else {
            return UsageSnapshot(
                timestamp: Date(), tokensUsed: 0, messageCount: 0,
                conversationId: nil, sessionLimitOverride: nil)
        }
        // Map premium interactions used% to tokensUsed out of 100 for the menubar badge
        let usedPercent: Int
        if let premium = response.quotaSnapshots.premiumInteractions, premium.hasPercentRemaining {
            usedPercent = Int(max(0, 100 - premium.percentRemaining).rounded())
        } else if let chat = response.quotaSnapshots.chat, chat.hasPercentRemaining {
            usedPercent = Int(max(0, 100 - chat.percentRemaining).rounded())
        } else {
            usedPercent = 0
        }
        return UsageSnapshot(
            timestamp: Date(),
            tokensUsed: usedPercent,
            messageCount: 0,
            conversationId: "copilot-quota",
            sessionLimitOverride: 100)
    }

    public func fetchSessions(limit: Int, offset: Int, groupByFolder: Bool, activeOnly: Bool) async throws -> [SessionSummary] {
        // Copilot has no session concept — return empty
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

    // MARK: - Quota Refresh

    private func refreshQuota() async throws {
        let response = try await fetcher.fetch()
        lastResponse = response
        lastFetchDate = Date()
        dataVersionCounter += 1
        latestQuotaDisplay = Self.makeDisplayData(from: response)
    }

    // MARK: - Display Mapping

    private static func makeDisplayData(from response: CopilotUsageResponse) -> CopilotQuotaDisplayData {
        let premium: CopilotQuotaDisplayData.QuotaItem?
        if let p = response.quotaSnapshots.premiumInteractions, p.hasPercentRemaining {
            let usedPercent = max(0, 100 - p.percentRemaining)
            premium = CopilotQuotaDisplayData.QuotaItem(
                label: "Premium Interactions",
                usedPercent: usedPercent,
                used: Int((p.entitlement - p.remaining).rounded()),
                total: Int(p.entitlement.rounded()))
        } else {
            premium = nil
        }

        let chat: CopilotQuotaDisplayData.QuotaItem?
        if let c = response.quotaSnapshots.chat, c.hasPercentRemaining {
            let usedPercent = max(0, 100 - c.percentRemaining)
            chat = CopilotQuotaDisplayData.QuotaItem(
                label: "Chat",
                usedPercent: usedPercent,
                used: Int((c.entitlement - c.remaining).rounded()),
                total: Int(c.entitlement.rounded()))
        } else {
            chat = nil
        }

        return CopilotQuotaDisplayData(
            plan: response.copilotPlan.capitalized,
            premiumInteractions: premium,
            chat: chat,
            resetDate: response.quotaResetDate,
            updatedAt: Date())
    }

    // MARK: - Token Resolution

    /// Try gh CLI hosts.yml first, then Keychain.
    static func resolveToken() -> String? {
        if let ghToken = readGHCLIToken() {
            return ghToken
        }
        return readKeychainToken()
    }

    /// Parse ~/.config/gh/hosts.yml for the api.github.com oauth_token.
    public static func readGHCLIToken() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let hostsPath = home.appendingPathComponent(".config/gh/hosts.yml").path

        guard let data = FileManager.default.contents(atPath: hostsPath),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        #if canImport(Yams)
        if let parsed = try? Yams.load(yaml: content) as? [String: Any],
           let github = parsed["github.com"] as? [String: Any],
           let token = github["oauth_token"] as? String, !token.isEmpty {
            return token
        }
        #endif

        // Fallback: simple line-based parsing for hosts.yml format
        return parseHostsYMLFallback(content)
    }

    /// Simple line parser for hosts.yml when Yams is unavailable or key structure differs.
    static func parseHostsYMLFallback(_ content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        var inGithubBlock = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("github.com:") {
                inGithubBlock = true
                continue
            }
            if inGithubBlock {
                if !line.hasPrefix(" ") && !line.hasPrefix("\t") && !trimmed.isEmpty {
                    break // left the github.com block
                }
                if trimmed.hasPrefix("oauth_token:") {
                    let value = trimmed.dropFirst("oauth_token:".count).trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { return value }
                }
            }
        }
        return nil
    }

    /// Read from Keychain: service=com.qstatus.copilot, account=github-oauth-token
    static func readKeychainToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.qstatus.copilot",
            kSecAttrAccount as String: "github-oauth-token",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Store token in Keychain for future use.
    public static func saveKeychainToken(_ token: String) {
        let data = Data(token.utf8)
        // Delete existing entry first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.qstatus.copilot",
            kSecAttrAccount as String: "github-oauth-token"
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.qstatus.copilot",
            kSecAttrAccount as String: "github-oauth-token",
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// Check if a Copilot token is available from any source.
    public static func isTokenAvailable() -> Bool {
        resolveToken() != nil
    }
}
