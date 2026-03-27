// ABOUTME: Tests for Copilot Enterprise quota models, fetcher, and token resolution.

import XCTest
@testable import Core

final class CopilotDataSourceTests: XCTestCase {

    // MARK: - Monthly Quotas Schema (Enterprise fallback)

    func testCopilotEnterpriseMonthlyQuotasFallback() throws {
        // Enterprise plans may use monthly_quotas + limited_user_quotas instead of quota_snapshots
        let json = """
        {
            "copilot_plan": "enterprise",
            "monthly_quotas": {
                "chat": 300,
                "completions": 1000
            },
            "limited_user_quotas": {
                "chat": 250,
                "completions": 680
            },
            "quota_reset_date": "2026-05-01"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CopilotUsageResponse.self, from: json)
        XCTAssertEqual(response.copilotPlan, "enterprise")
        XCTAssertEqual(response.quotaResetDate, "2026-05-01")

        // Premium interactions derived from completions: 680/1000 = 68% remaining
        let premium = try XCTUnwrap(response.quotaSnapshots.premiumInteractions)
        XCTAssertTrue(premium.hasPercentRemaining)
        XCTAssertEqual(premium.entitlement, 1000)
        XCTAssertEqual(premium.remaining, 680)
        XCTAssertEqual(premium.percentRemaining, 68, accuracy: 0.1)

        // Chat: 250/300 = 83.3% remaining
        let chat = try XCTUnwrap(response.quotaSnapshots.chat)
        XCTAssertTrue(chat.hasPercentRemaining)
        XCTAssertEqual(chat.entitlement, 300)
        XCTAssertEqual(chat.remaining, 250)
        XCTAssertEqual(chat.percentRemaining, 83.3, accuracy: 0.1)
    }

    // MARK: - Derive Percent When Missing

    func testCopilotMissingPercentRemainingDerived() throws {
        // When percent_remaining is absent but entitlement+remaining are present, derive it.
        let json = """
        {
            "copilot_plan": "business",
            "quota_snapshots": {
                "premium_interactions": {
                    "entitlement": 500,
                    "remaining": 200,
                    "quota_id": "premium_interactions"
                }
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CopilotUsageResponse.self, from: json)
        let premium = try XCTUnwrap(response.quotaSnapshots.premiumInteractions)
        XCTAssertTrue(premium.hasPercentRemaining)
        // 200/500 = 40% remaining
        XCTAssertEqual(premium.percentRemaining, 40, accuracy: 0.1)
    }

    // MARK: - Full quota_snapshots Schema

    func testCopilotQuotaSnapshotsSchema() throws {
        let json = """
        {
            "copilot_plan": "business",
            "quota_snapshots": {
                "premium_interactions": {
                    "entitlement": 1000,
                    "remaining": 320,
                    "percent_remaining": 32.0,
                    "quota_id": "premium_interactions"
                },
                "chat": {
                    "entitlement": 100,
                    "remaining": 88,
                    "percent_remaining": 88.0,
                    "quota_id": "chat"
                }
            },
            "quota_reset_date": "2026-04-01"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CopilotUsageResponse.self, from: json)
        XCTAssertEqual(response.copilotPlan, "business")

        let premium = try XCTUnwrap(response.quotaSnapshots.premiumInteractions)
        XCTAssertEqual(premium.percentRemaining, 32.0, accuracy: 0.01)
        XCTAssertEqual(premium.entitlement, 1000)
        XCTAssertEqual(premium.remaining, 320)

        let chat = try XCTUnwrap(response.quotaSnapshots.chat)
        XCTAssertEqual(chat.percentRemaining, 88.0, accuracy: 0.01)
    }

    // MARK: - Placeholder Detection

    func testCopilotPlaceholderSnapshotsIgnored() throws {
        // All-zero entries should be treated as placeholders
        let json = """
        {
            "copilot_plan": "business",
            "quota_snapshots": {
                "premium_interactions": {
                    "entitlement": 0,
                    "remaining": 0,
                    "percent_remaining": 0,
                    "quota_id": ""
                },
                "chat": {
                    "entitlement": 100,
                    "remaining": 50,
                    "percent_remaining": 50.0,
                    "quota_id": "chat"
                }
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CopilotUsageResponse.self, from: json)
        XCTAssertNil(response.quotaSnapshots.premiumInteractions)
        XCTAssertNotNil(response.quotaSnapshots.chat)
    }

    // MARK: - GH CLI Token Parsing

    func testReadGHCLITokenFromHostsYML() {
        let hostsContent = """
        github.com:
            oauth_token: gho_abc123xyz789
            user: testuser
            git_protocol: https
        """

        let token = CopilotDataSource.parseHostsYMLFallback(hostsContent)
        XCTAssertEqual(token, "gho_abc123xyz789")
    }

    func testReadGHCLITokenMissing() {
        let hostsContent = """
        gitlab.com:
            oauth_token: some_token
            user: testuser
        """

        let token = CopilotDataSource.parseHostsYMLFallback(hostsContent)
        XCTAssertNil(token)
    }

    func testReadGHCLITokenMultipleHosts() {
        let hostsContent = """
        gitlab.com:
            oauth_token: gitlab_token
        github.com:
            oauth_token: gho_real_github_token
            user: devuser
        """

        let token = CopilotDataSource.parseHostsYMLFallback(hostsContent)
        XCTAssertEqual(token, "gho_real_github_token")
    }

    // MARK: - Display Data Mapping

    func testCopilotDisplayDataMapping() throws {
        let json = """
        {
            "copilot_plan": "enterprise",
            "quota_snapshots": {
                "premium_interactions": {
                    "entitlement": 1000,
                    "remaining": 680,
                    "percent_remaining": 68.0,
                    "quota_id": "premium_interactions"
                },
                "chat": {
                    "entitlement": 100,
                    "remaining": 88,
                    "percent_remaining": 88.0,
                    "quota_id": "chat"
                }
            },
            "quota_reset_date": "2026-04-01"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CopilotUsageResponse.self, from: json)
        let premium = try XCTUnwrap(response.quotaSnapshots.premiumInteractions)
        let usedPercent = max(0, 100 - premium.percentRemaining)
        XCTAssertEqual(usedPercent, 32.0, accuracy: 0.01, "Premium used% should be 100 - 68 = 32")

        let used = Int((premium.entitlement - premium.remaining).rounded())
        XCTAssertEqual(used, 320)
    }

    // MARK: - Number Format Flexibility

    func testCopilotQuotaSnapshotNumericStringValues() throws {
        // API may return numbers as strings
        let json = """
        {
            "copilot_plan": "business",
            "quota_snapshots": {
                "chat": {
                    "entitlement": "200",
                    "remaining": "150",
                    "percent_remaining": "75",
                    "quota_id": "chat"
                }
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CopilotUsageResponse.self, from: json)
        let chat = try XCTUnwrap(response.quotaSnapshots.chat)
        XCTAssertEqual(chat.entitlement, 200)
        XCTAssertEqual(chat.remaining, 150)
        XCTAssertEqual(chat.percentRemaining, 75)
    }

    // MARK: - DataSource Protocol Conformance

    func testCopilotDataSourceConformsToProtocol() {
        let _: any DataSource = CopilotDataSource(token: "test")
        XCTAssertTrue(true, "CopilotDataSource conforms to DataSource protocol")
    }
}
