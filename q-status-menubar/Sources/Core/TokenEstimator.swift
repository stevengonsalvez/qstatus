import Foundation

public enum TokenEstimator {
    // Approx ratio used by Q when exact counts aren't present
    private static let charsPerToken = 4.0

    public struct Breakdown: Sendable {
        public let historyChars: Int
        public let contextFilesChars: Int
        public let toolsChars: Int
        public let systemChars: Int
        public let fallbackChars: Int
    }

    public static func estimateTokens(breakdown: Breakdown) -> Int {
        let sum = breakdown.historyChars + breakdown.contextFilesChars + breakdown.toolsChars + breakdown.systemChars
        if sum > 0 {
            // Apply category-based rounding up to nearest 10, then sum
            let userAssistantChars = breakdown.historyChars // split unknown; kept as history bucket
            let userAssistantTokens = roundUpToNearest10(tokens: Double(userAssistantChars) / charsPerToken)
            let contextTokens = roundUpToNearest10(tokens: Double(breakdown.contextFilesChars) / charsPerToken)
            let toolsTokens = roundUpToNearest10(tokens: Double(breakdown.toolsChars) / charsPerToken)
            let systemTokens = roundUpToNearest10(tokens: Double(breakdown.systemChars) / charsPerToken)
            return userAssistantTokens + contextTokens + toolsTokens + systemTokens
        } else {
            return roundUpToNearest10(tokens: Double(breakdown.fallbackChars) / charsPerToken)
        }
    }

    private static func roundUpToNearest10(tokens: Double) -> Int {
        // Implements: (char/4 + 5) / 10 * 10 → round to nearest 10 (0.5 up)
        return Int(((tokens + 5.0) / 10.0).rounded(.down) * 10.0)
    }

    // Slow-path: parse a JSON string and estimate by deep character count
    public static func estimate(from jsonString: String) -> (tokens: Int, messages: Int, cwd: String?, contextWindow: Int?, modelId: String?) {
        var totalChars = 0
        var messages = 0
        var cwd: String? = nil
        var contextWindow: Int? = nil
        var modelId: String? = nil

        if let data = jsonString.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let modelInfo = obj["model_info"] as? [String: Any] {
                if let cw = modelInfo["context_window_tokens"] as? Int { contextWindow = cw }
                if let mid = modelInfo["model_id"] as? String { modelId = mid }
            }
            if let env = obj["env_context"] as? [String: Any],
               let es = env["env_state"] as? [String: Any],
               let path = es["current_working_directory"] as? String { cwd = path }
            if let history = obj["history"] as? [Any] {
                messages = history.count
                for item in history { totalChars += deepCount(item) }
            } else {
                totalChars += deepCount(obj)
            }
        } else {
            totalChars = jsonString.count
        }

        let tokens = Int((Double(totalChars) / charsPerToken).rounded())
        return (tokens, messages, cwd, contextWindow, modelId)
    }

    // Slow-path with breakdown for details view
    public static func estimateBreakdown(from jsonString: String) -> (totalTokens: Int, messages: Int, cwd: String?, contextWindow: Int?, historyTokens: Int, contextFilesTokens: Int, toolsTokens: Int, systemTokens: Int, compactionMarkers: Bool, modelId: String?) {
        var historyChars = 0
        var userChars = 0
        var assistantChars = 0
        var ctxFilesChars = 0
        var toolsChars = 0
        var sysChars = 0
        var messages = 0
        var cwd: String? = nil
        var contextWindow: Int? = nil
        var modelId: String? = nil

        var markers = false
        if let data = jsonString.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let modelInfo = obj["model_info"] as? [String: Any] {
                if let cw = modelInfo["context_window_tokens"] as? Int { contextWindow = cw }
                if let mid = modelInfo["model_id"] as? String { modelId = mid }
            }
            if let env = obj["env_context"] as? [String: Any],
               let es = env["env_state"] as? [String: Any],
               let path = es["current_working_directory"] as? String { cwd = path }
            if let history = obj["history"] as? [Any] {
                messages = history.count
                for item in history {
                    historyChars += deepCount(item)
                    if let d = item as? [String: Any] {
                        if let u = d["user"] {
                            if deepContainsCompaction(u) { markers = true }
                            userChars += deepCount(u)
                        }
                        if let a = d["assistant"] {
                            if deepContainsCompaction(a) { markers = true }
                            assistantChars += deepCount(a)
                        }
                    }
                }
            }
            if let cm = obj["context_manager"] as? [String: Any] {
                if let files = cm["context_files"] as? [Any] { ctxFilesChars = deepCount(files) }
                if deepContainsCompaction(cm) { markers = true }
            }
            if let tools = obj["tool_manager"] { toolsChars = deepCount(tools) }
            if let sys = obj["system_prompts"] { sysChars = deepCount(sys) }
        } else {
            // Fallback: everything together
            historyChars = jsonString.count
        }

        // Apply category-based rounding to nearest 10 per /usage semantics
        let userTokens = roundUpToNearest10(tokens: Double(userChars) / charsPerToken)
        let assistantTokens = roundUpToNearest10(tokens: Double(assistantChars) / charsPerToken)
        let historyOnlyChars = max(0, historyChars - userChars - assistantChars)
        let historyOnlyTokens = roundUpToNearest10(tokens: Double(historyOnlyChars) / charsPerToken)
        let contextTokens = roundUpToNearest10(tokens: Double(ctxFilesChars) / charsPerToken)
        let toolsTokens = roundUpToNearest10(tokens: Double(toolsChars) / charsPerToken)
        let systemTokens = roundUpToNearest10(tokens: Double(sysChars) / charsPerToken)
        let totalTokens = userTokens + assistantTokens + historyOnlyTokens + contextTokens + toolsTokens + systemTokens
        return (totalTokens, messages, cwd, contextWindow,
                userTokens + assistantTokens + historyOnlyTokens,
                contextTokens,
                toolsTokens,
                systemTokens,
                markers,
                modelId)
    }

    private static func deepCount(_ any: Any) -> Int {
        if let s = any as? String { return s.count }
        if let d = any as? [String: Any] { return d.values.reduce(0) { $0 + deepCount($1) } }
        if let a = any as? [Any] { return a.reduce(0) { $0 + deepCount($1) } }
        return 0
    }

    private static func deepContainsCompaction(_ any: Any) -> Bool {
        if let s = any as? String {
            let ls = s.lowercased()
            // Heuristics: look for signs of compaction/summarization/truncation
            return ls.contains("overflow") || ls.contains("compact") || ls.contains("summariz") || ls.contains("truncat")
        }
        if let d = any as? [String: Any] { return d.values.contains { deepContainsCompaction($0) } }
        if let a = any as? [Any] { return a.contains { deepContainsCompaction($0) } }
        return false
    }
}
