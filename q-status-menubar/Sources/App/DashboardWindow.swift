// ABOUTME: Full-featured dashboard window for detailed analytics and session management
// Provides comprehensive view of usage data with tabs for different views

import SwiftUI
import Core

struct DashboardWindow: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var selectedTab: DashboardTab = .sessions

    enum DashboardTab: String, CaseIterable {
        case sessions = "Sessions"
        case analytics = "Analytics"
        case usage = "Usage Trends"

        var icon: String {
            switch self {
            case .sessions: return "list.bullet.rectangle"
            case .analytics: return "chart.bar.xaxis"
            case .usage: return "chart.line.uptrend.xyaxis"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and tabs
            VStack(spacing: 0) {
                HStack {
                    Text("Q-Status Dashboard")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    // Data source indicator
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.settings?.dataSourceType == .claudeCode ? "bolt.circle.fill" : "sparkle")
                            .font(.system(size: 12))
                            .foregroundStyle(viewModel.settings?.dataSourceType == .claudeCode ? .purple : .blue)
                        Text(viewModel.settings?.dataSourceType.displayName ?? "Unknown")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Refresh button
                    Button(action: { viewModel.forceRefresh?() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("Refresh data")
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // Tab selector
                Picker("Tab", selection: $selectedTab) {
                    ForEach(DashboardTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                Divider()
            }
            .background(Color(NSColor.windowBackgroundColor))

            // Tab content
            Group {
                switch selectedTab {
                case .sessions:
                    SessionsTabView(viewModel: viewModel)
                case .analytics:
                    AnalyticsTabView(viewModel: viewModel)
                case .usage:
                    UsageTrendsTabView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 800, height: 600)
    }
}

// MARK: - Sessions Tab
struct SessionsTabView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search and filter bar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search sessions...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

                Picker("Sort by", selection: $viewModel.sort) {
                    Text("Recent").tag(SessionSort.lastActivity)
                    Text("Usage %").tag(SessionSort.usage)
                    Text("Tokens").tag(SessionSort.tokens)
                    Text("Messages").tag(SessionSort.messages)
                    // Cost sorting not available in SessionSort enum
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                Toggle("Group by folder", isOn: Binding(
                    get: { viewModel.settings?.groupByFolder ?? false },
                    set: { viewModel.settings?.groupByFolder = $0 }
                ))
                .toggleStyle(.checkbox)
            }
            .padding()

            Divider()

            // Sessions list with better layout
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filteredSessions, id: \.id) { session in
                        SessionRowDetailed(session: session, viewModel: viewModel)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                    }
                }
                .padding(.horizontal)
            }

            // Footer with summary stats
            Divider()
            HStack {
                Text("\(filteredSessions.count) sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 20) {
                    Label("\(formatTokens(totalTokens)) tokens", systemImage: "number")
                    Label(CostEstimator.formatUSD(totalCost), systemImage: "dollarsign.circle")
                    Label("\(totalMessages) messages", systemImage: "message")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private var filteredSessions: [SessionSummary] {
        var sessions = viewModel.sessions

        if !searchText.isEmpty {
            sessions = sessions.filter { session in
                session.id.localizedCaseInsensitiveContains(searchText) ||
                (session.cwd?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return sessions.sorted(by: { (s1, s2) -> Bool in
            switch viewModel.sort {
            case .lastActivity:
                return (s1.internalRowID ?? 0) > (s2.internalRowID ?? 0)
            case .usage:
                return s1.usagePercent > s2.usagePercent
            case .tokens:
                return s1.tokensUsed > s2.tokensUsed
            case .messages:
                return s1.messageCount > s2.messageCount
            case .id:
                return s1.id < s2.id
            }
        })
    }

    private var totalTokens: Int {
        filteredSessions.reduce(0) { $0 + $1.tokensUsed }
    }

    private var totalCost: Double {
        filteredSessions.reduce(0) { $0 + $1.costUSD }
    }

    private var totalMessages: Int {
        filteredSessions.reduce(0) { $0 + $1.messageCount }
    }

    private func formatTokens(_ tokens: Int) -> String {
        tokens >= 1000 ? "\(tokens/1000)k" : "\(tokens)"
    }
}

struct SessionRowDetailed: View {
    let session: SessionSummary
    @ObservedObject var viewModel: UsageViewModel
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill((session.lastActivity ?? Date.distantPast).timeIntervalSinceNow > -300 ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)

            // Session info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(folderName(session.cwd ?? session.id))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    if let lastActivity = session.lastActivity, lastActivity.timeIntervalSinceNow > -300 {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                    }
                }

                Text(session.id)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Usage bar
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: session.usagePercent / 100.0)
                    .tint(contextPercentColor(session.usagePercent))
                    .frame(width: 120)

                Text("\(Int(session.usagePercent))% • \(formatTokens(session.tokensUsed))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Stats
            VStack(alignment: .trailing, spacing: 2) {
                Text(CostEstimator.formatUSD(session.costUSD))
                    .font(.system(size: 12, weight: .medium))
                Text("\(session.messageCount) msgs")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80, alignment: .trailing)

            // Action button
            Button(action: { viewModel.onSelectSession?(session) }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color(NSColor.selectedControlColor).opacity(0.1) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func formatTokens(_ tokens: Int) -> String {
        tokens >= 1000 ? "\(tokens/1000)k" : "\(tokens)"
    }

    private func folderName(_ path: String) -> String {
        path.components(separatedBy: "/").last ?? path
    }

    private func contextPercentColor(_ percent: Double) -> Color {
        if percent >= 90 { return .red }
        if percent >= 75 { return .orange }
        if percent >= 50 { return .yellow }
        return .green
    }
}

// MARK: - Analytics Tab
struct AnalyticsTabView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Period summary cards
                HStack(spacing: 16) {
                    StatCard(
                        title: "Today",
                        tokens: viewModel.tokensToday,
                        cost: viewModel.costToday,
                        messages: 0, // Not tracked per day
                        icon: "calendar.day.timeline.left",
                        color: .blue
                    )

                    StatCard(
                        title: "This Week",
                        tokens: viewModel.tokensWeek,
                        cost: viewModel.costWeek,
                        messages: 0, // Not tracked per week
                        icon: "calendar.badge.clock",
                        color: .purple
                    )

                    StatCard(
                        title: "This Month",
                        tokens: viewModel.tokensMonth,
                        cost: viewModel.costMonth,
                        messages: viewModel.messagesMonth,
                        icon: "calendar",
                        color: .orange
                    )
                }
                .padding(.horizontal)

                // Sparkline chart
                if !viewModel.sparkline.isEmpty {
                    GroupBox(label: Text("Usage Trend (Last 24 Hours)")) {
                        // Sparkline chart
                        GeometryReader { geo in
                            Path { path in
                                let values = viewModel.sparkline
                                let w = geo.size.width
                                let h = geo.size.height
                                let maxV = max(values.max() ?? 1.0, 1.0)
                                for (i, v) in values.enumerated() {
                                    let x = CGFloat(i) / CGFloat(max(values.count - 1, 1)) * w
                                    let y = h - CGFloat(v / maxV) * h
                                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                                }
                            }
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                        }
                            .frame(height: 150)
                            .padding()
                    }
                    .padding(.horizontal)
                }

                // Claude-specific analytics if applicable
                if viewModel.settings?.dataSourceType == .claudeCode,
                   let plan = viewModel.settings?.claudePlan,
                   plan != .free {
                    GroupBox(label: Text("Plan Usage")) {
                        ClaudePlanAnalytics(viewModel: viewModel)
                    }
                    .padding(.horizontal)
                }

                // Top sessions
                if !viewModel.globalTop.isEmpty {
                    GroupBox(label: Text("Top Sessions by Usage")) {
                        VStack(spacing: 8) {
                            ForEach(Array(viewModel.globalTop.prefix(10)), id: \.id) { session in
                                HStack {
                                    Text(folderName(session.cwd ?? session.id))
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                    ProgressView(value: session.usagePercent / 100.0)
                                        .tint(contextPercentColor(session.usagePercent))
                                        .frame(width: 100)
                                    Text("\(Int(session.usagePercent))%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 40, alignment: .trailing)
                                }
                            }
                        }
                        .padding()
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    private func folderName(_ path: String) -> String {
        path.components(separatedBy: "/").last ?? path
    }

    private func contextPercentColor(_ percent: Double) -> Color {
        if percent >= 90 { return .red }
        if percent >= 75 { return .orange }
        if percent >= 50 { return .yellow }
        return .green
    }
}

struct StatCard: View {
    let title: String
    let tokens: Int
    let cost: Double
    let messages: Int
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Spacer()
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label("\(formatTokens(tokens)) tokens", systemImage: "number")
                    .font(.caption)
                Label(CostEstimator.formatUSD(cost), systemImage: "dollarsign.circle")
                    .font(.caption)
                Label("\(messages) messages", systemImage: "message")
                    .font(.caption)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func formatTokens(_ tokens: Int) -> String {
        tokens >= 1000 ? "\(tokens/1000)k" : "\(tokens)"
    }
}

struct ClaudePlanAnalytics: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        if let plan = viewModel.settings?.claudePlan {
            VStack(spacing: 12) {
                // Token usage - show current context for active session
                if let activeSession = viewModel.activeClaudeSession {
                    ProgressRow(
                        label: "Token Usage",
                        current: activeSession.tokens,  // Current context tokens
                        limit: 200_000,  // Context window limit
                        formatter: { t in
                            let tokens = t as! Int
                            return tokens >= 1000 ? "\(tokens/1000)k" : "\(tokens)"
                        }
                    )
                } else {
                    // No active session - show monthly stats
                    HStack {
                        Text("Token Usage")
                            .font(.caption)
                        Spacer()
                        Text("\(viewModel.tokensMonth >= 1_000_000 ? String(format: "%.1fM", Double(viewModel.tokensMonth) / 1_000_000) : "\(viewModel.tokensMonth / 1000)k") (30-day total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Cost usage - always show monthly cost vs plan limit
                ProgressRow(
                    label: "Cost Usage",
                    current: viewModel.costMonth,
                    limit: plan.costLimit > 0 ? plan.costLimit : Double.infinity,
                    formatter: { c in CostEstimator.formatUSD(c as! Double) }
                )

                // Messages (informational only)
                HStack {
                    Label("Messages", systemImage: "message")
                        .font(.caption)
                    Spacer()
                    Text("\(viewModel.messagesMonth)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
}

struct ProgressRow: View {
    let label: String
    let current: Any
    let limit: Any
    let formatter: (Any) -> String

    var percentage: Double {
        if let currentInt = current as? Int, let limitInt = limit as? Int {
            return limitInt > 0 ? Double(currentInt) / Double(limitInt) : 0
        } else if let currentDouble = current as? Double, let limitDouble = limit as? Double {
            return limitDouble > 0 ? currentDouble / limitDouble : 0
        }
        return 0
    }

    var progressColor: Color {
        if percentage >= 0.9 { return .red }
        if percentage >= 0.75 { return .orange }
        if percentage >= 0.5 { return .yellow }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text("\(formatter(current)) / \(formatter(limit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(1.0, percentage))
                .tint(progressColor)
        }
    }
}

// MARK: - Usage Trends Tab
struct UsageTrendsTabView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Usage Trends")
                    .font(.title3)
                    .fontWeight(.medium)
                    .padding(.top)

                if !viewModel.sparkline.isEmpty {
                    // 24-hour trend
                    GroupBox(label: Text("24-Hour Activity")) {
                        VStack(alignment: .leading, spacing: 12) {
                            // Sparkline chart
                        GeometryReader { geo in
                            Path { path in
                                let values = viewModel.sparkline
                                let w = geo.size.width
                                let h = geo.size.height
                                let maxV = max(values.max() ?? 1.0, 1.0)
                                for (i, v) in values.enumerated() {
                                    let x = CGFloat(i) / CGFloat(max(values.count - 1, 1)) * w
                                    let y = h - CGFloat(v / maxV) * h
                                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                                }
                            }
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                        }
                                .frame(height: 200)

                            HStack {
                                ForEach(["Now", "6h", "12h", "18h", "24h"], id: \.self) { label in
                                    Text(label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if label != "24h" { Spacer() }
                                }
                            }
                        }
                        .padding()
                    }
                    .padding(.horizontal)
                }

                // Burn rate if active
                if let activeSession = viewModel.activeClaudeSession {
                    GroupBox(label: Text("Current Burn Rate")) {
                        BurnRateView(
                            activeSession: activeSession,
                            settings: viewModel.settings ?? SettingsStore(),
                            messagesMonth: viewModel.messagesMonth,
                            costMonth: viewModel.costMonth
                        )
                        .padding()
                    }
                    .padding(.horizontal)
                }

                // Historical patterns (placeholder for future enhancement)
                GroupBox(label: Text("Usage Patterns")) {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Peak usage time:")
                                .font(.caption)
                            Spacer()
                            Text("2:00 PM - 5:00 PM")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Average session duration:")
                                .font(.caption)
                            Spacer()
                            Text("45 minutes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Most active project:")
                                .font(.caption)
                            Spacer()
                            Text(folderName(viewModel.sessions.first?.cwd ?? "Unknown"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding()
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 20)
        }
    }

    private func folderName(_ path: String) -> String {
        path.components(separatedBy: "/").last ?? path
    }
}