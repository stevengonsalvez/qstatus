import Foundation

public final class MetricsCalculator: @unchecked Sendable {
    public init() {}

    public func usagePercent(used: Int, limit: Int) -> Double {
        guard limit > 0 else { return 0 }
        return min(100.0, max(0.0, (Double(used) / Double(limit)) * 100.0))
    }

    public func tokensPerMinute(history: [UsageSnapshot]) -> Double {
        guard history.count >= 2 else { return 0 }
        let sorted = history.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first, let last = sorted.last, last.timestamp > first.timestamp else { return 0 }
        let deltaTokens = max(0, last.tokensUsed - first.tokensUsed)
        let deltaMinutes = last.timestamp.timeIntervalSince(first.timestamp) / 60.0
        return deltaMinutes > 0 ? Double(deltaTokens) / deltaMinutes : 0
    }

    public func timeToLimit(remaining: Int, ratePerMin: Double) -> TimeInterval? {
        guard ratePerMin > 0, remaining > 0 else { return nil }
        return Double(remaining) / ratePerMin * 60.0
    }

    public func healthState(for percent: Double) -> HealthState {
        if percent >= 90 { return .critical }
        if percent >= 70 { return .warning }
        if percent <= 0 { return .idle }
        return .healthy
    }
}

