// ABOUTME: Tests for Codex CLI session file parsing, rate limit extraction, and active session detection.

import XCTest
@testable import Core

final class CodexDataSourceTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Active Session Detection by Mtime

    func testCodexActiveSessionDetectionByMtime() throws {
        // Create two JSONL files: one old, one recent
        let sessionsDir = tempDir.appendingPathComponent("sessions/2026/03/27")
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        let oldFile = sessionsDir.appendingPathComponent("rollout-old-aaa.jsonl")
        let newFile = sessionsDir.appendingPathComponent("rollout-new-bbb.jsonl")

        let content = """
        {"type":"session_meta","id":"test-id","timestamp":"2026-03-27T10:00:00Z","cwd":"/tmp/project"}
        """
        try content.write(to: oldFile, atomically: true, encoding: .utf8)
        try content.write(to: newFile, atomically: true, encoding: .utf8)

        // Set old file to 2 days ago
        let oldDate = Date().addingTimeInterval(-172800)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: oldFile.path)

        // New file has current mtime (just written)
        let found = CodexDataSource.findActiveSessionFile(in: tempDir)
        XCTAssertEqual(found?.lastPathComponent, "rollout-new-bbb.jsonl",
                        "Should pick the most recently modified file")
    }

    // MARK: - Rate Limits Extraction from JSONL

    func testCodexRateLimitsExtractionFromJSONL() throws {
        let file = tempDir.appendingPathComponent("session.jsonl")
        let jsonl = """
        {"type":"session_meta","id":"sess-123","timestamp":"2026-03-27T10:00:00Z","cwd":"/home/user/project","model_provider":"anthropic","cli_version":"1.0"}
        {"type":"event_msg","rate_limits":{"primary":{"used_percent":45.2,"window_minutes":300,"resets_at":1711234567},"secondary":{"used_percent":12.1,"window_minutes":10080,"resets_at":1711834567},"credits":{"has_credits":true,"unlimited":false,"balance":4.20},"plan_type":"pro"}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let session = try CodexDataSource.parseSessionFile(file)

        let rl = try XCTUnwrap(session.rateLimits)
        XCTAssertEqual(rl.primaryUsedPercent, 45.2, accuracy: 0.01)
        XCTAssertEqual(rl.primaryWindowMinutes, 300)
        XCTAssertEqual(rl.secondaryUsedPercent, 12.1, accuracy: 0.01)
        XCTAssertEqual(rl.secondaryWindowMinutes, 10080)
        XCTAssertEqual(try XCTUnwrap(rl.creditsBalance), 4.20, accuracy: 0.01)
        XCTAssertFalse(rl.creditsUnlimited)
        XCTAssertEqual(rl.planType, "pro")
        XCTAssertEqual(session.sessionId, "sess-123")
        XCTAssertEqual(session.cwd, "/home/user/project")
    }

    // MARK: - Inactive Session After 1 Hour

    func testCodexInactiveSessionAfter1Hour() throws {
        let file = tempDir.appendingPathComponent("old-session.jsonl")
        let jsonl = """
        {"type":"session_meta","id":"old-sess","cwd":"/tmp/old"}
        {"type":"event_msg","rate_limits":{"primary":{"used_percent":10,"window_minutes":300,"resets_at":1711234567},"secondary":{"used_percent":5,"window_minutes":10080,"resets_at":1711834567},"credits":{"has_credits":false,"unlimited":true},"plan_type":"max"}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        // Set mtime to 2 hours ago
        let twoHoursAgo = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes(
            [.modificationDate: twoHoursAgo],
            ofItemAtPath: file.path)

        let session = try CodexDataSource.parseSessionFile(file, inactiveThreshold: 3600)
        XCTAssertFalse(session.isActive, "Session modified >1h ago should be inactive")
    }

    func testCodexActiveSessionWithin1Hour() throws {
        let file = tempDir.appendingPathComponent("active-session.jsonl")
        let jsonl = """
        {"type":"session_meta","id":"active-sess","cwd":"/tmp/active"}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        // File was just written, mtime is now
        let session = try CodexDataSource.parseSessionFile(file, inactiveThreshold: 3600)
        XCTAssertTrue(session.isActive, "Session modified just now should be active")
    }

    // MARK: - Session Meta CWD Extraction

    func testCodexSessionMetaCwdExtraction() throws {
        let file = tempDir.appendingPathComponent("cwd-session.jsonl")
        let jsonl = """
        {"type":"session_meta","id":"s1","cwd":"/Users/dev/projects/myapp","model_provider":"anthropic"}
        {"type":"turn_context","cwd":"/Users/dev/projects/myapp","model":"claude-opus-4","summary":"fixing bug"}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let session = try CodexDataSource.parseSessionFile(file)
        XCTAssertEqual(session.cwd, "/Users/dev/projects/myapp")
        XCTAssertEqual(session.model, "claude-opus-4")
        XCTAssertEqual(session.sessionId, "s1")
    }

    // MARK: - Handles Missing Rate Limits

    func testCodexHandlesMissingRateLimits() throws {
        let file = tempDir.appendingPathComponent("no-rl-session.jsonl")
        let jsonl = """
        {"type":"session_meta","id":"no-rl","cwd":"/tmp/test"}
        {"type":"turn_context","cwd":"/tmp/test","model":"claude-sonnet-4","summary":"hello world"}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let session = try CodexDataSource.parseSessionFile(file)
        XCTAssertNil(session.rateLimits, "Should be nil when no event_msg with rate_limits exists")
        XCTAssertEqual(session.cwd, "/tmp/test")
        XCTAssertEqual(session.model, "claude-sonnet-4")
    }

    // MARK: - Last Event Wins (Reverse Parsing)

    func testCodexLastRateLimitsEventWins() throws {
        let file = tempDir.appendingPathComponent("multi-event.jsonl")
        let jsonl = """
        {"type":"session_meta","id":"s1","cwd":"/tmp/project"}
        {"type":"event_msg","rate_limits":{"primary":{"used_percent":10,"window_minutes":300,"resets_at":1711234567},"secondary":{"used_percent":2,"window_minutes":10080,"resets_at":1711834567},"credits":{"has_credits":true,"unlimited":false,"balance":10.00},"plan_type":"pro"}}
        {"type":"turn_context","cwd":"/tmp/project","model":"claude-opus-4","summary":"first turn"}
        {"type":"event_msg","rate_limits":{"primary":{"used_percent":55.5,"window_minutes":300,"resets_at":1711234567},"secondary":{"used_percent":15.3,"window_minutes":10080,"resets_at":1711834567},"credits":{"has_credits":true,"unlimited":false,"balance":3.80},"plan_type":"pro"}}
        {"type":"turn_context","cwd":"/tmp/project","model":"claude-opus-4","summary":"second turn"}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let session = try CodexDataSource.parseSessionFile(file)
        let rl = try XCTUnwrap(session.rateLimits)
        // Last event_msg has 55.5% primary
        XCTAssertEqual(rl.primaryUsedPercent, 55.5, accuracy: 0.01)
        XCTAssertEqual(rl.secondaryUsedPercent, 15.3, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(rl.creditsBalance), 3.80, accuracy: 0.01)
    }

    // MARK: - Unlimited Credits

    func testCodexUnlimitedCreditsHidesBalance() throws {
        let file = tempDir.appendingPathComponent("unlimited.jsonl")
        let jsonl = """
        {"type":"session_meta","id":"u1","cwd":"/tmp"}
        {"type":"event_msg","rate_limits":{"primary":{"used_percent":20,"window_minutes":300,"resets_at":1711234567},"secondary":{"used_percent":5,"window_minutes":10080,"resets_at":1711834567},"credits":{"has_credits":true,"unlimited":true,"balance":999.99},"plan_type":"max"}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let session = try CodexDataSource.parseSessionFile(file)
        let rl = try XCTUnwrap(session.rateLimits)
        XCTAssertTrue(rl.creditsUnlimited)
        XCTAssertNil(rl.creditsBalance, "Balance should be nil when unlimited")
        XCTAssertEqual(rl.planType, "max")
    }

    // MARK: - Display CWD Truncation

    func testCodexDisplayCwdTruncation() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let session = CodexSessionData(
            rateLimits: nil,
            cwd: home + "/d/git/myproject",
            model: nil,
            sessionId: nil,
            lastActivity: Date(),
            isActive: true
        )
        XCTAssertEqual(session.displayCwd, "~/d/git/myproject")
    }

    func testCodexDisplayCwdNonHomePath() {
        let session = CodexSessionData(
            rateLimits: nil,
            cwd: "/opt/projects/something",
            model: nil,
            sessionId: nil,
            lastActivity: Date(),
            isActive: true
        )
        XCTAssertEqual(session.displayCwd, "/opt/projects/something")
    }

    // MARK: - No Sessions Directory

    func testCodexNoActiveSessionFileWhenDirectoryMissing() {
        let nonexistent = tempDir.appendingPathComponent("does-not-exist")
        let found = CodexDataSource.findActiveSessionFile(in: nonexistent)
        XCTAssertNil(found)
    }

    // MARK: - DataSource Protocol Conformance

    func testCodexDataSourceConformsToProtocol() {
        let _: any DataSource = CodexDataSource(sessionsDirectory: tempDir)
        XCTAssertTrue(true, "CodexDataSource conforms to DataSource protocol")
    }

    // MARK: - Empty JSONL File

    func testCodexEmptyJSONLFile() throws {
        let file = tempDir.appendingPathComponent("empty.jsonl")
        try "".write(to: file, atomically: true, encoding: .utf8)

        let session = try CodexDataSource.parseSessionFile(file)
        XCTAssertNil(session.rateLimits)
        XCTAssertNil(session.cwd)
        XCTAssertNil(session.model)
        XCTAssertNil(session.sessionId)
    }
}
