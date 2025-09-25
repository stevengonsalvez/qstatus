import SwiftUI
import AppKit
#if canImport(Charts)
import Charts
#endif
import Core

// Helper to make sheet windows movable and properly positioned
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                // Make window movable
                window.isMovableByWindowBackground = true
                window.styleMask.insert(.fullSizeContentView)

                // Center window on screen
                if let screen = NSScreen.main {
                    let screenFrame = screen.visibleFrame
                    let windowFrame = window.frame
                    let x = (screenFrame.width - windowFrame.width) / 2 + screenFrame.origin.x
                    let y = (screenFrame.height - windowFrame.height) / 2 + screenFrame.origin.y
                    window.setFrameOrigin(NSPoint(x: x, y: y))
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct DropdownView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var topSort: TopSort = .tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Plan selector for Claude Code users
            if viewModel.settings?.dataSourceType == .claudeCode {
                claudePlanSelector
                Divider()
            }

            // Global header with totals
            globalHeaderSection

            // Active Claude Code Session and Plan Usage
            if viewModel.settings?.dataSourceType == .claudeCode {
                claudeCodeSection
            }

            Divider()

            // Recent Sessions header block
            recentSessionsSection

            Divider()

            // Compact view - show only 3 recent sessions
            compactSessionsList

            Divider()

            // View Dashboard button for detailed analytics
            HStack {
                Spacer()
                Button(action: { viewModel.showAllSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 12))
                        Text("View Dashboard")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.05)))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .help("Open full dashboard with analytics and all sessions (⌘⇧Q)")
                Spacer()
            }

            // Provider selector
            providerSelectorSection

            Divider()

            // Control buttons
            controlButtonsSection
        }
        .padding(14)
        .frame(width: 500)
        .sheet(item: Binding(get: { viewModel.selectedSession }, set: { _ in viewModel.selectedSession = nil })) { details in
            SessionDetailView(details: details, messagesMonth: viewModel.messagesMonth)
                .frame(width: 420, height: 400)
                .padding()
        }
        .sheet(isPresented: $viewModel.showAllSheet) {
            DashboardWindow(viewModel: viewModel)
                .frame(width: 800, height: 600)
                .background(WindowAccessor())
        }
        // Trigger reloads when filters change
        .onChange(of: viewModel.settings?.groupByFolder ?? false) { _ in viewModel.forceRefresh?() }
    }

    // MARK: - Extracted View Sections

    @ViewBuilder
    private var globalHeaderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.settings?.dataSourceType == .claudeCode {
                claudeCodeHeader
            } else {
                amazonQHeader
            }

            // Burn rate removed - shown in BurnRateView instead
        }
    }

    @ViewBuilder
    private var claudeCodeHeader: some View {
        // Claude Code specific header showing plan usage
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Text("Overall").font(.headline)
                Text("•")
                    .foregroundStyle(.secondary)
                Image(systemName: "bolt.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .help("Data source: Claude Code")
            }
            Spacer()

            // Show current session block usage percentage or current cost if no plan
            if let plan = viewModel.settings?.claudePlan {
                if plan == .free {
                    // Show current 30-day cost when no plan selected
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(CostEstimator.formatUSD(viewModel.costMonth))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                        Text("No plan")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .help("30-day cost: \(CostEstimator.formatUSD(viewModel.costMonth)). Select a plan to see usage percentage.")
                } else {
                    // Show current 5-hour session block usage percentage
                    sessionBlockPercentageView(plan: plan)
                }
            }
        }
        .font(.caption)

        // Overall (30-day stats)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "chart.bar.fill")
                Text("Overall")
                Text("• Session Context")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Sessions: \(viewModel.globalSessions) • Tokens: \(formatTokens(viewModel.tokensMonth)) • Cost: \(CostEstimator.formatUSD(viewModel.costMonth))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                HStack {
                    Text("Messages: \(viewModel.messagesMonth) (last 30 days)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }

        HStack {
            Text("Rolling: 30-day \(CostEstimator.formatUSD(viewModel.costMonth)) • 7-day \(CostEstimator.formatUSD(viewModel.costWeek))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("Detailed", isOn: detailedModeBinding)
                .toggleStyle(.switch)
                .font(.caption)
                .help("Show sparkline visualization and period totals")
        }
        .font(.caption)
    }

    @ViewBuilder
    private var amazonQHeader: some View {
        // Amazon Q header (original)
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Text("Overall").font(.headline)
                Text("•")
                    .foregroundStyle(.secondary)
                Image(systemName: "sparkle")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .help("Data source: Amazon Q")
            }
            Spacer()
            // Only show percentage when we have active sessions and not in group mode
            if !(viewModel.settings?.groupByFolder ?? false),
               !viewModel.sessions.isEmpty,
               let ctx = activeSessionContextPercent() {
                Text("\(ctx)%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(contextPercentColor(Double(ctx) ?? 0))
                    .help("Most recent session context usage")
            }
        }
        .font(.caption)

        // Amazon Q totals
        if viewModel.globalSessions > 0 {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Sessions: \(viewModel.globalSessions) • Tokens: \(formatTokens(viewModel.globalTokens)) • Cost: \(CostEstimator.formatUSD(viewModel.globalCost))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }

        HStack {
            Text("Rolling Costs: 30-day \(CostEstimator.formatUSD(viewModel.costMonth)) • 7-day \(CostEstimator.formatUSD(viewModel.costWeek))")
            Spacer()
            Toggle("Detailed", isOn: detailedModeBinding)
                .toggleStyle(.switch)
                .font(.caption)
                .help("Show sparkline visualization and period totals")
        }
        .font(.caption)
    }


    @ViewBuilder
    private var claudeCodeSection: some View {
        // Always show the plan usage view, even for free plan
        ClaudeCodeUsageView(viewModel: viewModel)
            .transition(.opacity)

        // Show active session details if there is one
        if let activeSession = viewModel.activeClaudeSession {
            Divider()
            activeClaudeSessionDetails(activeSession)
        }
    }

    @ViewBuilder
    private func activeClaudeSessionDetails(_ activeSession: ActiveSessionData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Session header
            sessionHeader(activeSession)

            // Session info
            sessionInfoRow(activeSession)

            // Token limit progress
            if let settings = viewModel.settings {
                tokenLimitProgress(activeSession, settings)
            }

            // Time to Reset
            timeToResetView(activeSession)

            // Burn rate display with predictions
            if let settings = viewModel.settings {
                BurnRateView(
                    activeSession: activeSession,
                    settings: settings,
                    messagesMonth: viewModel.messagesMonth,
                    costMonth: viewModel.costMonth
                )
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func timeToResetView(_ activeSession: ActiveSessionData) -> some View {
        HStack {
            Label("Time to Reset", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()

            // Calculate time remaining in the 5-hour block
            let blockEndTime = activeSession.startTime.addingTimeInterval(5 * 3600)  // 5 hours from start
            let now = Date()
            let timeRemaining = blockEndTime.timeIntervalSince(now)

            if timeRemaining > 0 {
                let hours = Int(timeRemaining / 3600)
                let minutes = Int((timeRemaining.truncatingRemainder(dividingBy: 3600)) / 60)
                Text("\(hours)h \(minutes)m")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(timeRemaining < 1800 ? .orange : .green)  // Orange if less than 30 min
            } else {
                Text("Expired")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func sessionHeader(_ activeSession: ActiveSessionData) -> some View {
        HStack {
            Label("Active Session", systemImage: "circle.fill")
                .font(.caption)
                .foregroundStyle(activeSession.isActive ? .green : .orange)
            Spacer()
            if activeSession.isActive {
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green)
                    .cornerRadius(4)
            } else {
                Text("Recent")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func sessionInfoRow(_ activeSession: ActiveSessionData) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let cwd = activeSession.cwd {
                    Text(folderName(cwd))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(cwd)
                }
                Text("Started: \(activeSession.startTime, style: .relative)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            sessionStatsColumn(activeSession)
        }
    }

    @ViewBuilder
    private func sessionStatsColumn(_ activeSession: ActiveSessionData) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 6) {
                Text("\(formatTokens(activeSession.tokens))")
                    .font(.system(size: 11, weight: .medium))
                    .help("Context tokens (current memory)")

                costDisplay(activeSession)
            }

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(activeSession.messageCount) messages")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text("\(formatBurnRate(activeSession.messagesPerHour)) msgs/hr")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .help("Message burn rate: \(String(format: "%.1f", activeSession.messagesPerHour)) messages per hour")
            }
        }
    }

    @ViewBuilder
    private func costDisplay(_ activeSession: ActiveSessionData) -> some View {
        if activeSession.costFromJSONL {
            Text("\(CostEstimator.formatUSD(activeSession.cost))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green)
        } else {
            HStack(spacing: 2) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
                    .help("Estimated cost")
                Text("\(CostEstimator.formatUSD(activeSession.cost))")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func tokenLimitProgress(_ activeSession: ActiveSessionData, _ settings: SettingsStore) -> some View {
        let percentage = settings.claudeTokenLimitPercentage(currentTokens: activeSession.tokens)
        let isWarning = settings.isApproachingClaudeLimit(currentTokens: activeSession.tokens)

        VStack(alignment: .leading, spacing: 4) {
            // Context limit header
            HStack {
                Text("Context Limit")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                if isWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(percentage >= 95 ? .red : .orange)
                        .help("Approaching token limit")
                }
                Text("\(Int(percentage))% of \(formatTokens(settings.claudeTokenLimit))")
                    .font(.system(size: 9))
                    .foregroundStyle(isWarning ? (percentage >= 95 ? .red : .orange) : .secondary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tokenLimitColor(percentage))
                        .frame(width: geo.size.width * min(1.0, percentage / 100.0))
                }
            }
            .frame(height: 4)

            // Cumulative tokens display
            HStack {
                Text("Context Usage")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(formatTokens(activeSession.tokens)) tokens")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .help("Current context tokens in memory (after compaction)")
                    Text("\(formatTokens(Int(activeSession.tokensPerHour)))/hr")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .help("Token burn rate: \(formatTokens(Int(activeSession.tokensPerHour))) tokens per hour")
                }
            }
        }
    }

    @ViewBuilder
    private var recentSessionsSection: some View {
        if !viewModel.sessions.isEmpty {
            let recentSessions = Array(viewModel.sessions.sorted {
                ($0.internalRowID ?? 0) > ($1.internalRowID ?? 0)
            }.prefix(5))

            if !recentSessions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Context: Recent sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 4) {
                        ForEach(recentSessions, id: \.id) { session in
                            recentSessionRow(session)
                        }
                    }
                }
                Divider()
            }
        }
    }

    @ViewBuilder
    private func recentSessionRow(_ session: SessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Folder name above the bar
            Text(folderName(session.cwd ?? session.id))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(session.cwd ?? session.id)

            HStack(spacing: 8) {
                // Compact progress bar showing context usage
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.2))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(contextPercentColor(session.usagePercent))
                            .frame(width: geo.size.width * min(1.0, session.usagePercent / 100.0))
                    }
                }
                .frame(height: 6)

                Text("\(Int(session.usagePercent))%")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)

                Text("\(formatTokens(session.tokensUsed))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private var periodFooterSection: some View {
        VStack(spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Today").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(formatTokens(viewModel.tokensToday)) • \(CostEstimator.formatUSD(viewModel.costToday))")
                        .font(.caption)
                }
                GridRow {
                    Text("Week").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(formatTokens(viewModel.tokensWeek)) • \(CostEstimator.formatUSD(viewModel.costWeek))")
                        .font(.caption)
                }
                GridRow {
                    Text("Month").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(formatTokens(viewModel.tokensMonth)) • \(CostEstimator.formatUSD(viewModel.costMonth))")
                        .font(.caption)
                }
            }

            // Message count footer line
            HStack {
                Text("Monthly Messages:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.messagesMonth)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var sessionsListSection: some View {
        if !viewModel.sessions.isEmpty {
            VStack(spacing: 8) {
                // Sessions list header
                sessionsListHeader

                // Search field
                TextField("Search by id or folder…", text: $viewModel.searchQuery)
                    .textFieldStyle(.roundedBorder)

                // Sessions scroll view
                sessionsScrollView

                HStack {
                    Spacer()
                }
            }
            Divider()
        }
    }

    @ViewBuilder
    private var sessionsListHeader: some View {
        HStack(spacing: 12) {
            Text("Sessions")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("Group", isOn: groupByFolderBinding)
                .toggleStyle(.switch)
                .help("One session per folder")
            Picker("Sort", selection: $viewModel.sort) {
                Text("Recent").tag(SessionSort.lastActivity)
                Text("Usage").tag(SessionSort.usage)
                Text("Tokens").tag(SessionSort.tokens)
                Text("Messages").tag(SessionSort.messages)
                Text("ID").tag(SessionSort.id)
            }
            .pickerStyle(.menu)
            Button { viewModel.forceRefresh?() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh now")
        }
    }

    @ViewBuilder
    private var sessionsScrollView: some View {
        ScrollView {
            VStack(spacing: 8) {
                if viewModel.settings?.dataSourceType == .claudeCode &&
                   viewModel.settings?.groupByFolder ?? false {
                    groupedSessionsList
                } else {
                    flatSessionsList
                }
            }
        }
        .frame(height: 150)
    }

    @ViewBuilder
    private var groupedSessionsList: some View {
        let grouped = Dictionary(grouping: filteredSortedSessions) { $0.cwd ?? "Unknown" }
        ForEach(grouped.keys.sorted(), id: \.self) { folder in
            DisclosureGroup {
                ForEach(grouped[folder]!, id: \.id) { session in
                    Button(action: { viewModel.onSelectSession?(session) }) {
                        SessionRow(session: session, categories: viewModel.sessionCategoryTokens[session.id])
                    }
                    .buttonStyle(ClickableRowButtonStyle())
                    .help("Click to view session details")
                    .padding(.leading, 10)
                }
            } label: {
                groupedSessionsHeader(folder: folder, sessions: grouped[folder]!)
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func groupedSessionsHeader(folder: String, sessions: [SessionSummary]) -> some View {
        HStack {
            Image(systemName: "folder.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(folderName(folder))
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Total tokens and cost for this folder
            let totalTokens = sessions.reduce(0) { $0 + $1.tokensUsed }
            let totalCost = sessions.reduce(0) { $0 + $1.costUSD }
            Text("\(formatTokens(totalTokens)) • \(CostEstimator.formatUSD(totalCost))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var flatSessionsList: some View {
        ForEach(filteredSortedSessions, id: \.id) { s in
            Button(action: { viewModel.onSelectSession?(s) }) {
                SessionRow(session: s, categories: viewModel.sessionCategoryTokens[s.id])
            }
            .buttonStyle(ClickableRowButtonStyle())
            .help("Click to view session details")
        }
    }

    @ViewBuilder
    private var topSessionsSection: some View {
        if !viewModel.globalTop.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                // Top sessions header
                HStack {
                    Text("Top Sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Sort", selection: $topSort) {
                        Text("Tokens").tag(TopSort.tokens)
                            .help("Sort by total tokens used")
                        Text("Usage").tag(TopSort.usage)
                            .help("Sort by context usage percentage")
                        Text("Cost").tag(TopSort.cost)
                            .help("Sort by cost in USD")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                // Top sessions list
                VStack(spacing: 6) {
                    let sorted = topSortedGlobalTop().prefix(5)
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, s in
                        TopSessionRow(session: s, onSelect: { viewModel.onSelectSession?(s) })
                            .id("\(s.id)-\(topSort.rawValue)")
                    }
                }

                HStack {
                    ViewAllButton(action: { viewModel.onOpenAll?() })
                    Spacer()
                }
            }
            Divider()
        }
    }

    @ViewBuilder
    private var providerSelectorSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Data Source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.isSwitchingProvider {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            HStack(spacing: 8) {
                ForEach(DataSourceType.allCases, id: \.self) { provider in
                    providerButton(provider)
                }
            }
        }
    }

    @ViewBuilder
    private func providerButton(_ provider: DataSourceType) -> some View {
        Button(action: {
            if provider != viewModel.settings?.dataSourceType {
                viewModel.switchProvider(to: provider)
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: provider.iconName)
                    .font(.caption)
                    .foregroundStyle(provider == .amazonQ ? .blue : .purple)
                Text(provider.displayName)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(viewModel.settings?.dataSourceType == provider ?
                          Color.accentColor.opacity(0.2) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(viewModel.settings?.dataSourceType == provider ?
                           Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(viewModel.isSwitchingProvider)
    }

    @ViewBuilder
    private var compactSessionsList: some View {
        if !viewModel.sessions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                compactSessionsHeader
                compactSessionsRows
            }
        }
    }

    @ViewBuilder
    private var compactSessionsHeader: some View {
        HStack {
            Text("Recent Activity")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(viewModel.sessions.count) sessions")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var compactSessionsRows: some View {
        let recentSessions = Array(viewModel.sessions.sorted {
            ($0.internalRowID ?? 0) > ($1.internalRowID ?? 0)
        }.prefix(3))

        VStack(spacing: 6) {
            ForEach(recentSessions, id: \.id) { session in
                compactSessionRow(session)
            }
        }
    }

    @ViewBuilder
    private func compactSessionRow(_ session: SessionSummary) -> some View {
        HStack(spacing: 8) {
            // Status dot
            Circle()
                .fill((session.lastActivity ?? Date.distantPast).timeIntervalSinceNow > -300 ? Color.green : Color.gray)
                .frame(width: 6, height: 6)

            // Folder name
            Text(folderName(session.cwd ?? session.id))
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Stats
            compactSessionStats(session)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.05))
        )
        .onTapGesture {
            viewModel.onSelectSession?(session)
        }
    }

    @ViewBuilder
    private func compactSessionStats(_ session: SessionSummary) -> some View {
        HStack(spacing: 4) {
            Text("\(Int(session.usagePercent))%")
                .font(.caption2)
                .foregroundStyle(contextPercentColor(session.usagePercent))
                .frame(width: 35, alignment: .trailing)

            Text("•")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(formatTokens(session.tokensUsed))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 45, alignment: .trailing)

            Text("•")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text("\(session.messageCount) msgs")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var claudePlanSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Claude Plan", systemImage: "bolt.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.purple)
                Spacer()
            }

            // Plan selection grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ClaudePlan.allCases, id: \.self) { plan in
                    Button(action: {
                        viewModel.settings?.claudePlan = plan
                        viewModel.settings?.saveToDisk()
                        viewModel.forceRefresh?()
                    }) {
                        HStack(spacing: 6) {
                            // Checkmark for selected plan
                            if viewModel.settings?.claudePlan == plan {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.gray.opacity(0.5))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(plan.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(viewModel.settings?.claudePlan == plan ? .primary : .secondary)

                                if plan != .free {
                                    Text(plan == .custom ? "Custom limits" : "$\(Int(plan.costLimit))/mo")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(viewModel.settings?.claudePlan == plan ?
                                    Color.accentColor.opacity(0.15) :
                                    Color.gray.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(viewModel.settings?.claudePlan == plan ?
                                    Color.accentColor.opacity(0.3) :
                                    Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // Show current limits for selected plan
            if let plan = viewModel.settings?.claudePlan, plan != .free {
                HStack(spacing: 12) {
                    Label("\(formatTokens(plan.tokenLimit))", systemImage: "number")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)

                    Label("\(plan.messageLimit) msgs", systemImage: "message")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.top, 4)
            }

            // Custom plan configuration if selected
            if viewModel.settings?.claudePlan == .custom {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom limits configured in Preferences")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Button("Configure Custom Limits…") {
                        viewModel.openPreferences()
                    }
                    .font(.system(size: 10))
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var controlButtonsSection: some View {
        HStack {
            Button("Preferences…") { viewModel.openPreferences() }
            Spacer()
            Button(action: { viewModel.forceRefresh?() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .help("Refresh now")
            Button(viewModel.isPaused ? "Resume" : "Pause") { viewModel.togglePause() }
            Button("Quit") { viewModel.quit() }
        }
    }

    // MARK: - Computed Properties

    private var detailedModeBinding: Binding<Bool> {
        Binding(
            get: { !(viewModel.settings?.compactMode ?? true) },
            set: { viewModel.settings?.compactMode = !$0 }
        )
    }

    private var groupByFolderBinding: Binding<Bool> {
        Binding(
            get: { viewModel.settings?.groupByFolder ?? false },
            set: { viewModel.settings?.groupByFolder = $0 }
        )
    }

    private var summaryLine: String {
        if viewModel.totalSessions > 0 {
            return "\(viewModel.totalSessions) sessions • total \(viewModel.totalTokens) tokens"
        } else {
            return viewModel.subtitle
        }
    }

    private var globalSummaryLine: String {
        if viewModel.globalSessions > 0 {
            return "All: \(viewModel.globalSessions) sessions • \(viewModel.globalTokens) tokens"
        } else if viewModel.totalSessions > 0 {
            return "\(viewModel.totalSessions) sessions • total \(viewModel.totalTokens) tokens"
        } else {
            return viewModel.subtitle
        }
    }
}

struct UsageSparkline: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxV = max(values.max() ?? 1.0, 1.0)
            Path { path in
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) / CGFloat(max(values.count - 1, 1)) * w
                    let y = h - CGFloat(v / maxV) * h
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
    }
}

@ViewBuilder
fileprivate func UsageSparklineCombined(values: [Double]) -> some View {
#if canImport(Charts)
    Chart {
        ForEach(Array(values.enumerated()), id: \.offset) { idx, v in
            LineMark(
                x: .value("Index", idx),
                y: .value("Tokens", v)
            )
        }
    }
#else
    UsageSparkline(values: values)
#endif
}

// View helpers
extension DropdownView {
    fileprivate func costRatePerMin() -> Double {
        let ratePer1k = viewModel.weightedRatePer1k
        return (viewModel.globalTokensPerMinute / 1000.0) * ratePer1k
    }
    private var filteredSortedSessions: [SessionSummary] {
        var arr = viewModel.sessions
        if !viewModel.searchQuery.isEmpty {
            let q = viewModel.searchQuery.lowercased()
            arr = arr.filter { $0.id.lowercased().contains(q) || ($0.cwd?.lowercased().contains(q) ?? false) }
        }
        switch viewModel.sort {
        case .lastActivity:
            return arr.sorted { ($0.internalRowID ?? 0) > ($1.internalRowID ?? 0) }
        case .usage:
            return arr.sorted { $0.usagePercent > $1.usagePercent }
        case .tokens:
            return arr.sorted { $0.tokensUsed > $1.tokensUsed }
        case .messages:
            return arr.sorted { $0.messageCount > $1.messageCount }
        case .id:
            return arr.sorted { $0.id < $1.id }
        }
    }
    fileprivate var showDetailed: Bool { !(viewModel.settings?.compactMode ?? true) }
    fileprivate func contextPercentColor(_ percent: Double) -> Color {
        if percent >= 90 { return .red }
        if percent >= 70 { return .orange }
        if percent >= 50 { return .yellow }
        return .green
    }

    private func calculateSessionBlockPercentage(plan: ClaudePlan) -> (percent: Double, tokens: Int, cost: Double) {
        if let activeSession = viewModel.activeClaudeSession {
            // For the current 5-hour session block, we need to show:
            // - The context usage (tokens currently in memory)
            // - Against the context window limit (200K for most models)

            let contextTokens = activeSession.tokens  // Current context tokens (not cumulative)
            let cost = activeSession.cost  // Session cost

            // Use context window limit for percentage calculation
            // This matches what Claude Code Usage Monitor shows
            let contextWindow = viewModel.settings?.claudeTokenLimit ?? 200_000
            let percent = PercentageCalculator.calculateTokenPercentage(
                tokens: contextTokens,
                limit: contextWindow
            )

            return (percent, contextTokens, cost)
        } else {
            // No active session
            return (0, 0, 0)
        }
    }

    @ViewBuilder
    private func sessionBlockPercentageView(plan: ClaudePlan) -> some View {
        let sessionData = calculateSessionBlockPercentage(plan: plan)
        let contextWindow = viewModel.settings?.claudeTokenLimit ?? 200_000

        VStack(spacing: 2) {
            Text("\(Int(sessionData.percent))%")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(costPercentColor(sessionData.percent))

            Text("Session")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .help("Session context usage: \(formatTokens(sessionData.tokens)) of \(formatTokens(contextWindow)) tokens • Session cost: \(CostEstimator.formatUSD(sessionData.cost))")
    }

    fileprivate func costPercentColor(_ percent: Double) -> Color {
        if percent >= 95 { return .red }
        if percent >= 80 { return .orange }
        if percent >= 60 { return .yellow }
        return .green
    }
    fileprivate func activeSessionContextPercent() -> String? {
        guard let s = viewModel.sessions.sorted(by: { ($0.internalRowID ?? 0) > ($1.internalRowID ?? 0) }).first else { return nil }
        let p = min(100.0, max(0.0, s.usagePercent))
        if p < 0.1 { return String(format: "%.1f", p) } // show 0.x
        return String(format: "%.0f", p)
    }
    fileprivate func topSortedGlobalTop() -> [SessionSummary] {
        // Sort with stable secondary sort by rowID for consistency
        switch topSort {
        case .tokens:
            return viewModel.globalTop.sorted {
                if $0.tokensUsed != $1.tokensUsed {
                    return $0.tokensUsed > $1.tokensUsed
                }
                return ($0.internalRowID ?? 0) > ($1.internalRowID ?? 0)
            }
        case .usage:
            return viewModel.globalTop.sorted {
                if $0.usagePercent != $1.usagePercent {
                    return $0.usagePercent > $1.usagePercent
                }
                return ($0.internalRowID ?? 0) > ($1.internalRowID ?? 0)
            }
        case .cost:
            return viewModel.globalTop.sorted {
                if $0.costUSD != $1.costUSD {
                    return $0.costUSD > $1.costUSD
                }
                return ($0.internalRowID ?? 0) > ($1.internalRowID ?? 0)
            }
        }
    }
    fileprivate func shortId(_ id: String) -> String { id.count > 10 ? String(id.prefix(8)) + "…" : id }
    fileprivate func formatTokens(_ t: Int) -> String {
        if t >= 1_000_000 {
            return String(format: "%.1fM", Double(t) / 1_000_000)
        } else if t >= 10_000 {
            return String(format: "%.0fK", Double(t) / 1_000)
        } else if t >= 1_000 {
            return String(format: "%.1fK", Double(t) / 1_000)
        } else {
            return "\(t)"
        }
    }
    fileprivate func cwdTail2(_ p: String) -> String {
        let comps = p.split(separator: "/").filter { !$0.isEmpty }
        if comps.count >= 2 { return comps.suffix(2).joined(separator: "/") }
        return comps.last.map(String.init) ?? p
    }

    fileprivate func folderName(_ p: String) -> String {
        // Extract just the last folder component for display
        let comps = p.split(separator: "/").filter { !$0.isEmpty }
        return comps.last.map(String.init) ?? p
    }

    fileprivate func formatBurnRate(_ rate: Double) -> String {
        if rate < 1 {
            return String(format: "%.1f", rate)
        } else if rate < 10 {
            return String(format: "%.1f", rate)
        } else {
            return String(format: "%.0f", rate)
        }
    }

    fileprivate func messageQuotaColor(_ messages: Int) -> Color {
        let colorName = PercentageCalculator.getMessageQuotaColor(messages: messages)
        switch colorName {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        default: return .secondary
        }
    }

    fileprivate func tokenLimitColor(_ percentage: Double) -> Color {
        if percentage >= 95 { return .red }
        if percentage >= 80 { return .orange }
        if percentage >= 60 { return .yellow }
        return .green
    }

    fileprivate func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        } else if minutes > 0 {
            return "\(minutes)m remaining"
        } else {
            return "< 1m remaining"
        }
    }

    fileprivate func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    fileprivate func progressBarColor(_ percentage: Double) -> Color {
        if percentage >= 90 { return .red }
        if percentage >= 70 { return .orange }
        return .green
    }
}

private enum TopSort: String, CaseIterable { case tokens, usage, cost }

// Custom button style for clickable session rows
struct ClickableRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) :
                          configuration.isPressed ? Color.accentColor.opacity(0.15) : Color.clear)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
                    .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

// Custom view for Top Session rows with hover effects
struct TopSessionRow: View {
    let session: SessionSummary
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Text(cwdTail2(session.cwd ?? session.id))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(isHovered ? .primary : .secondary)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)

                Spacer()

                Text("\(formatTokens(session.tokensUsed)) • \(Int(session.usagePercent))% • \(CostEstimator.formatUSD(session.costUSD)) • \(session.messageCount) msgs")
                    .font(.caption2)
                    .foregroundColor(isHovered ? .primary : .secondary)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)

                // Chevron indicator showing it's clickable
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isHovered ? Color.blue : Color.blue.opacity(0.85))
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
            }
        }
        .buttonStyle(ClickableRowButtonStyle())
        .help("Click to view session details")
    }

    private func cwdTail2(_ p: String) -> String {
        let comps = p.split(separator: "/").filter { !$0.isEmpty }
        if comps.count >= 2 { return comps.suffix(2).joined(separator: "/") }
        return comps.last.map(String.init) ?? p
    }

    private func formatTokens(_ t: Int) -> String {
        t >= 1000 ? "\(t/1000)k" : "\(t)"
    }
}

// Custom button for View All with enhanced styling
struct ViewAllButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("View All")
                    .font(.system(.caption, weight: .medium))
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor : Color.accentColor.opacity(0.8))
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
            )
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        .help("View all sessions with pagination")
    }
}

struct SessionDetailView: View {
    let details: SessionDetails
    let messagesMonth: Int
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(details.summary.id).font(.system(.caption, design: .monospaced))
                    if let cwd = details.summary.cwd { Label(cwd, systemImage: "folder") .font(.caption) }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    ProgressView(value: min(max(details.summary.usagePercent/100.0, 0), 1))
                        .tint(color(for: details.summary))
                        .frame(width: 160)
                    Text("\(formatTokens(details.summary.tokensUsed)) / \(formatTokens(details.summary.contextWindow)) • \(Int(details.summary.usagePercent))%")
                        .font(.caption)
                }
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow { Text("History"); Spacer(); Text("\(formatTokens(details.historyTokens))") }
                GridRow { Text("Context Files"); Spacer(); Text("\(formatTokens(details.contextFilesTokens))") }
                GridRow { Text("Tools"); Spacer(); Text("\(formatTokens(details.toolsTokens))") }
                GridRow { Text("System Prompts"); Spacer(); Text("\(formatTokens(details.systemTokens))") }
                GridRow { Text("Messages"); Spacer(); Text("\(details.summary.messageCount)") }
            }
            Divider()
            // Footer with standardized information
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Session Cost:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(CostEstimator.formatUSD(details.summary.costUSD))
                        .font(.caption)
                }
                HStack {
                    Text("Monthly Messages:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(messagesMonth)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack {
                Button("Copy ID") { copyToClipboard(details.summary.id) }
                if let cwd = details.summary.cwd { Button("Reveal in Finder") { revealInFinder(cwd) } }
                Spacer()
                Button("Close") { dismiss() }
            }
        }
    }
    private func color(for s: SessionSummary) -> Color {
        switch s.state { case .critical: return .red; case .warn: return .yellow; default: return .green }
    }
    private func formatTokens(_ t: Int) -> String { t >= 1000 ? "\(t/1000)k" : "\(t)" }
    private func copyToClipboard(_ s: String) {
        let p = NSPasteboard.general
        p.clearContents()
        p.setString(s, forType: .string)
    }
    private func revealInFinder(_ p: String) {
        let expanded = (p as NSString).expandingTildeInPath
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: expanded)])
    }
    private func messageQuotaColor(_ messages: Int) -> Color {
        let colorName = PercentageCalculator.getMessageQuotaColor(messages: messages)
        switch colorName {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        default: return .secondary
        }
    }
}

struct SessionRow: View {
    let session: SessionSummary
    let categories: (history:Int, context:Int, tools:Int, system:Int)?
    @State private var isParentHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                // Always show something - either folder name or session ID
                HStack(spacing: 4) {
                    if let cwd = session.cwd, !cwd.isEmpty {
                        Image(systemName: "folder")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(folderName(cwd))
                            .truncationMode(.tail)
                            .lineLimit(1)
                            .help(cwd)
                            .font(.caption)
                            .foregroundStyle(.primary)
                    } else {
                        // Show session ID - if it looks like a path, extract folder name
                        let displayName = session.id.contains("/") ? folderName(session.id) : shortId(session.id)
                        Image(systemName: session.id.contains("/") ? "folder" : "doc.text")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(displayName)
                            .truncationMode(.tail)
                            .help("Session: \(session.id)")
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }
            }
            Spacer()

            // Chevron indicator for clickability
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.blue)
                .imageScale(.medium)

            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: min(max(session.usagePercent/100.0, 0), 1))
                    .tint(color(for: session))
                    .frame(width: 120)
                if let c = categories {
                    StackedBar(history: c.history, context: c.context, tools: c.tools, system: c.system)
                        .frame(width: 120, height: 6)
                }
                Text("\(formatTokens(session.tokensUsed)) / \(formatTokens(session.contextWindow)) • \(Int(session.usagePercent))% • \(CostEstimator.formatUSD(session.costUSD)) • \(session.messageCount) msgs")
                    .font(.caption2)
            }
            if session.hasCompactionIndicators {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
                    .help("Compaction activity detected")
            }
        }
    }
    private func shortId(_ id: String) -> String { id.count > 10 ? String(id.prefix(8)) + "…" : id }
    private func cwdTail(_ p: String) -> String { (p as NSString).lastPathComponent }
    private func folderName(_ p: String) -> String {
        // Extract just the last folder component for display
        let comps = p.split(separator: "/").filter { !$0.isEmpty }
        return comps.last.map(String.init) ?? p
    }
    private func formatTokens(_ t: Int) -> String {
        if t >= 1000 { return "\(t/1000)k" } else { return "\(t)" }
    }
    private func color(for s: SessionSummary) -> Color {
        switch s.state { case .critical: return .red; case .warn: return .yellow; default: return .green }
    }
}

struct StackedBar: View {
    let history: Int; let context: Int; let tools: Int; let system: Int
    var body: some View {
        let total = max(1, history + context + tools + system)
        HStack(spacing: 0) {
            Rectangle().fill(Color.mint).frame(width: width(for: history, total: total))
            Rectangle().fill(Color.cyan).frame(width: width(for: context, total: total))
            Rectangle().fill(Color.red).frame(width: width(for: tools, total: total))
            Rectangle().fill(Color.blue).frame(width: width(for: system, total: total))
        }
        .cornerRadius(2)
    }
    private func width(for part: Int, total: Int) -> CGFloat { CGFloat(part) / CGFloat(total) * 120.0 }
}

struct AllSessionsSheet: View {
    @ObservedObject var viewModel: UsageViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("All Sessions")
                    .font(.headline)
                Spacer()
                Text("Page \(viewModel.page + 1) • Total \(viewModel.totalSessionsCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                TextField("Search…", text: $viewModel.searchQuery)
                    .textFieldStyle(.roundedBorder)
                Picker("Sort", selection: $viewModel.sort) {
                    Text("Recent").tag(SessionSort.lastActivity)
                    Text("Usage").tag(SessionSort.usage)
                    Text("Tokens").tag(SessionSort.tokens)
                    Text("Messages").tag(SessionSort.messages)
                    Text("ID").tag(SessionSort.id)
                }
                .pickerStyle(.menu)
            }
            Divider()
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(filteredSortedAll, id: \.id) { s in
                        Button(action: { viewModel.onSelectSession?(s) }) {
                            SessionRow(session: s, categories: viewModel.sessionCategoryTokens[s.id])
                        }
                        .buttonStyle(ClickableRowButtonStyle())
                        .help("Click to view session details")
                    }
                }
            }
            // Footer for this page: day/week/month subset totals with message quota
            Divider()
            VStack(spacing: 8) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Page Today").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(formatTokens(viewModel.sheetTokensDay)) • \(CostEstimator.formatUSD(viewModel.sheetCostDay))").font(.caption)
                    }
                    GridRow {
                        Text("Page Week").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(formatTokens(viewModel.sheetTokensWeek)) • \(CostEstimator.formatUSD(viewModel.sheetCostWeek))").font(.caption)
                    }
                    GridRow {
                        Text("Page Month").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(formatTokens(viewModel.sheetTokensMonth)) • \(CostEstimator.formatUSD(viewModel.sheetCostMonth))").font(.caption)
                    }
                }
                // Message count footer line
                HStack {
                    Text("Monthly Messages:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(viewModel.messagesMonth)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Button("Previous") { viewModel.onPrevPage?() }
                    .disabled(viewModel.page == 0)
                Button("Next") { viewModel.onNextPage?() }
                    .disabled((viewModel.page + 1) * 50 >= max(viewModel.totalSessionsCount, 0))
                Spacer()
                Button("Close") { viewModel.showAllSheet = false }
            }
        }
        .padding()
    }
    private var filteredSortedAll: [SessionSummary] {
        var arr = viewModel.allSessions
        if !viewModel.searchQuery.isEmpty {
            let q = viewModel.searchQuery.lowercased()
            arr = arr.filter { $0.id.lowercased().contains(q) || ($0.cwd?.lowercased().contains(q) ?? false) }
        }
        switch viewModel.sort {
        case .lastActivity:
            return arr.sorted { ($0.internalRowID ?? 0) > ($1.internalRowID ?? 0) }
        case .usage:
            return arr.sorted { $0.usagePercent > $1.usagePercent }
        case .tokens:
            return arr.sorted { $0.tokensUsed > $1.tokensUsed }
        case .messages:
            return arr.sorted { $0.messageCount > $1.messageCount }
        case .id:
            return arr.sorted { $0.id < $1.id }
        }
    }

    private func formatTokens(_ t: Int) -> String { t >= 1000 ? "\(t/1000)k" : "\(t)" }

    private func messageQuotaColor(_ messages: Int) -> Color {
        let colorName = PercentageCalculator.getMessageQuotaColor(messages: messages)
        switch colorName {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        default: return .secondary
        }
    }
}

// Burn rate display with predictions for Claude Code
struct BurnRateView: View {
    let activeSession: ActiveSessionData
    let settings: SettingsStore
    let messagesMonth: Int
    let costMonth: Double  // Add monthly cost for accurate predictions

    // Calculate burn rates from current block if available
    private var blockBurnRates: (tokens: Double, cost: Double, messages: Double) {
        if let currentBlock = activeSession.currentBlock,
           let burnRate = BurnRateCalculator.calculateBurnRate(for: currentBlock) {
            // Use burn rate from current 5-hour block (excluding cache tokens for display)
            let blockTokensPerHour = burnRate.tokensPerMinuteForIndicator * 60  // Convert to per hour, using indicator rate
            let blockCostPerHour = burnRate.costPerHour

            // Calculate messages per hour from block
            let blockDuration = currentBlock.actualEndTime?.timeIntervalSince(currentBlock.startTime) ?? 0
            let blockHours = max(0.01, blockDuration / 3600.0)
            let blockMessagesPerHour = Double(currentBlock.entries.count) / blockHours

            return (blockTokensPerHour, blockCostPerHour, blockMessagesPerHour)
        } else {
            // Fallback to session-wide rates
            return (activeSession.tokensPerHour, activeSession.costPerHour, activeSession.messagesPerHour)
        }
    }

    var body: some View {
        let sessionDuration = activeSession.lastActivity.timeIntervalSince(activeSession.startTime)
        let minutesElapsed = sessionDuration / 60.0

        // Only show if session has been running for at least 1 minute
        if minutesElapsed >= 1.0 {
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    // Header with icon
                    HStack {
                        Label("Burn Rate & Predictions", systemImage: "flame.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                    }

                    // Burn rates grid
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        GridRow {
                            HStack(spacing: 4) {
                                Image(systemName: "flame")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Text("Tokens")
                            }
                            .font(.caption2)
                            Spacer()
                            Text(formatBurnRate(blockBurnRates.tokens, type: .tokens))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }

                        GridRow {
                            HStack(spacing: 4) {
                                Image(systemName: "dollarsign.circle")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Text("Cost")
                            }
                            .font(.caption2)
                            Spacer()
                            Text(formatBurnRate(blockBurnRates.cost, type: .cost))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }

                        GridRow {
                            HStack(spacing: 4) {
                                Image(systemName: "message")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Text("Messages")
                            }
                            .font(.caption2)
                            Spacer()
                            Text(formatBurnRate(blockBurnRates.messages, type: .messages))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                    }

                    Divider()
                        .padding(.vertical, 2)

                    // Predictions
                    VStack(alignment: .leading, spacing: 3) {
                        if let predictions = calculatePredictions() {
                            ForEach(predictions, id: \.type) { prediction in
                                HStack {
                                    Image(systemName: prediction.icon)
                                        .font(.system(size: 9))
                                        .foregroundStyle(prediction.color)
                                    Text(prediction.text)
                                        .font(.system(size: 9))
                                        .foregroundStyle(prediction.color)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private enum BurnRateType {
        case tokens, cost, messages
    }

    private struct Prediction: Identifiable {
        let id = UUID()
        let type: String
        let text: String
        let icon: String
        let color: Color
    }

    private func formatBurnRate(_ rate: Double, type: BurnRateType) -> String {
        switch type {
        case .tokens:
            // Display as tokens/min to match Claude Code Monitor
            let perMin = rate / 60.0
            if perMin < 1000 {
                return String(format: "%.0f tokens/min", perMin)
            } else {
                return String(format: "%.1f K/min", perMin / 1000.0)
            }

        case .cost:
            // Display as $/min to match Claude Code Monitor
            let perMin = rate / 60.0
            return String(format: "$%.4f/min", perMin)

        case .messages:
            // Choose appropriate unit based on rate
            if rate < 1 { // Less than 1/hour, show per day
                let perDay = rate * 24
                return String(format: "%.1f msgs/day", perDay)
            } else if rate < 60 { // Less than 60/hour
                return String(format: "%.1f msgs/hr", rate)
            } else { // High rate, show per minute
                let perMin = rate / 60.0
                return String(format: "%.1f msgs/min", perMin)
            }
        }
    }

    private func calculatePredictions() -> [Prediction]? {
        var predictions: [Prediction] = []

        // Get plan limits
        let plan = settings.claudePlan
        guard plan != .free else { return nil }

        // Calculate time remaining in the 5-hour session window
        let sessionStartTime = activeSession.startTime
        let sessionEndTime = sessionStartTime.addingTimeInterval(5 * 3600) // 5 hours from start
        let now = Date()
        let sessionTimeRemaining = sessionEndTime.timeIntervalSince(now) / 3600 // in hours

        // Only make predictions if we have time left in the session
        guard sessionTimeRemaining > 0 else {
            predictions.append(Prediction(
                type: "session",
                text: "Session expired - will reset",
                icon: "clock.badge.exclamationmark",
                color: .red
            ))
            return predictions
        }

        // Calculate burn rate from current block instead of entire session
        let blockTokensPerHour: Double
        let blockCostPerHour: Double

        if let currentBlock = activeSession.currentBlock,
           let burnRate = BurnRateCalculator.calculateBurnRate(for: currentBlock) {
            // Use burn rate from current 5-hour block (use indicator rate for realistic predictions)
            blockTokensPerHour = burnRate.tokensPerMinuteForIndicator * 60  // Convert to per hour
            blockCostPerHour = burnRate.costPerHour
        } else {
            // Fallback to session-wide burn rate if no block data
            blockTokensPerHour = activeSession.tokensPerHour
            blockCostPerHour = activeSession.costPerHour
        }

        // Token limit prediction - when will we hit context limit
        let contextLimit = settings.claudeTokenLimit
        let currentTokens = activeSession.tokens
        let remainingTokens = max(0, contextLimit - currentTokens)

        // Use the block burn rate for predictions
        if blockTokensPerHour > 0 && remainingTokens > 0 {
            let hoursToTokenLimit = Double(remainingTokens) / blockTokensPerHour

            // Check if we'll hit the limit before session reset
            if hoursToTokenLimit < sessionTimeRemaining {
                let tokenPrediction = formatPredictionTime(hours: hoursToTokenLimit, limitType: "Context limit")
                predictions.append(Prediction(
                    type: "tokens",
                    text: tokenPrediction.text,
                    icon: "exclamationmark.triangle.fill",
                    color: tokenPrediction.color
                ))
            }
        }

        // Cost limit prediction for the session
        // Calculate projected cost for this 5-hour block
        if let currentBlock = activeSession.currentBlock {
            let currentBlockCost = currentBlock.costUSD

            // Project total cost if we continue at block burn rate for the full 5 hours
            let projectedSessionCost = currentBlockCost + (blockCostPerHour * sessionTimeRemaining)

            // For cost-based plans, check against per-session limit
            if plan.costLimit > 0 {
                // Daily limit = monthly limit / 30
                // Session limit (5 hours) = daily limit * (5/24)
                let dailyLimit = plan.costLimit / 30.0
                let sessionLimit = dailyLimit * (5.0 / 24.0)

                if projectedSessionCost > sessionLimit {
                    // Calculate when we'll exceed the session cost limit
                    let remainingBudget = max(0, sessionLimit - currentBlockCost)
                    if blockCostPerHour > 0 && remainingBudget > 0 {
                        let hoursToCostLimit = remainingBudget / blockCostPerHour
                        if hoursToCostLimit < sessionTimeRemaining {
                            let costPrediction = formatPredictionTime(hours: hoursToCostLimit, limitType: "Cost limit")
                            predictions.append(Prediction(
                                type: "cost",
                                text: costPrediction.text,
                                icon: "dollarsign.circle.fill",
                                color: costPrediction.color
                            ))
                        }
                    } else if projectedSessionCost > sessionLimit * 1.5 {
                        // Already significantly over limit
                        predictions.append(Prediction(
                            type: "cost",
                            text: "Cost limit exceeded!",
                            icon: "exclamationmark.octagon.fill",
                            color: .red
                        ))
                    }
                }
            }
        }

        // Add session reset time as informational (only if we have other predictions)
        if !predictions.isEmpty {
            predictions.append(Prediction(
                type: "reset",
                text: String(format: "Session resets at %@",
                            DateFormatter.localizedString(from: sessionEndTime,
                                                         dateStyle: .none,
                                                         timeStyle: .short)),
                icon: "clock.arrow.circlepath",
                color: .secondary
            ))
        }

        return predictions.isEmpty ? nil : predictions
    }

    private func extractHoursFromPrediction(_ text: String) -> Double {
        // This is a simplified extraction - in practice we'd pass the hours value through
        if text.contains("min") {
            return 0.5 // Less than an hour
        } else if text.contains("hour") {
            return 12 // Approximate
        } else if text.contains("day") {
            return 48 // Approximate
        }
        return 999 // Unknown/far future
    }

    private func formatPredictionTime(hours: Double, limitType: String) -> (text: String, color: Color) {
        // Handle negative or very small values
        if hours <= 0 {
            return ("\(limitType) reached", .red)
        } else if hours < 1 {
            let minutes = max(1, Int(hours * 60))  // Always show at least 1 minute
            return ("\(limitType) in ~\(minutes) min", .red)
        } else if hours < 24 {
            let wholeHours = Int(hours)
            return ("\(limitType) in ~\(wholeHours) hr\(wholeHours == 1 ? "" : "s")", hours < 6 ? .red : .orange)
        } else {
            let days = Int(hours / 24)
            return ("\(limitType) in ~\(days) day\(days == 1 ? "" : "s")", .yellow)
        }
    }
}

// Claude Code Usage View with Compact/Expanded modes
struct ClaudeCodeUsageView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var isExpanded: Bool = false
    @State private var shouldAutoExpand: Bool = false

    // Computed properties for limits
    private var tokenLimit: Int {
        // Try to get max from previous sessions first (like ccusage)
        if let maxFromPrevious = viewModel.maxTokensFromPreviousBlocks,
           maxFromPrevious > 0 {
            return maxFromPrevious
        }

        // Fall back to plan limits
        guard let plan = viewModel.settings?.claudePlan, plan != .free else { return 0 }
        if plan == .custom {
            return viewModel.settings?.customPlanTokenLimit ?? 200_000
        } else {
            return plan.tokenLimit
        }
    }

    private var costLimit: Double {
        guard let plan = viewModel.settings?.claudePlan, plan != .free else { return 0 }
        if plan == .custom {
            return viewModel.settings?.customPlanCostLimit ?? 100.0
        } else {
            return plan.costLimit
        }
    }

    // Current values
    private var currentTokens: Int {
        if let activeSession = viewModel.activeClaudeSession,
           let block = activeSession.currentBlock {
            // Use the block's total tokens for percentage calculation
            return block.tokenCounts.totalTokens
        } else if let activeSession = viewModel.activeClaudeSession {
            return activeSession.tokens  // Fallback to context tokens
        } else {
            return 0  // No active session means no current context
        }
    }

    private var currentCost: Double {
        if let activeSession = viewModel.activeClaudeSession,
           let block = activeSession.currentBlock {
            // Use the block's cost for percentage calculation
            return block.costUSD
        } else if let activeSession = viewModel.activeClaudeSession {
            return activeSession.cost
        } else {
            return viewModel.costMonth
        }
    }

    private var currentMessages: Int {
        if let activeSession = viewModel.activeClaudeSession {
            return activeSession.messageCount
        } else {
            return viewModel.messagesMonth
        }
    }

    // Messages in current billing block (if active session)
    private var messagesInBlock: Int? {
        if let activeSession = viewModel.activeClaudeSession,
           activeSession.currentBlock != nil {
            // Return messages in current block
            return activeSession.messageCount
        }
        return nil
    }

    // Percentages - Use centralized calculator
    private var tokenPercentage: Double {
        if let activeSession = viewModel.activeClaudeSession,
           let block = activeSession.currentBlock {
            return PercentageCalculator.calculateTokenPercentage(
                tokens: block.tokenCounts.totalTokens,
                maxFromPrevious: viewModel.maxTokensFromPreviousBlocks
            )
        } else if let activeSession = viewModel.activeClaudeSession {
            return PercentageCalculator.calculateTokenPercentage(
                tokens: activeSession.tokens,
                maxFromPrevious: viewModel.maxTokensFromPreviousBlocks
            )
        } else {
            // For monthly view, use token limit
            return PercentageCalculator.calculateTokenPercentage(
                tokens: currentTokens,
                limit: tokenLimit
            )
        }
    }

    private var costPercentage: Double {
        if let activeSession = viewModel.activeClaudeSession,
           let block = activeSession.currentBlock {
            return PercentageCalculator.calculateCostPercentage(
                cost: block.costUSD,
                useBlockBaseline: true
            )
        } else if let activeSession = viewModel.activeClaudeSession {
            return PercentageCalculator.calculateCostPercentage(
                cost: activeSession.cost,
                useBlockBaseline: true
            )
        } else {
            // For monthly view, use cost limit
            return PercentageCalculator.calculateCostPercentage(
                cost: currentCost,
                useBlockBaseline: false,
                monthlyLimit: costLimit
            )
        }
    }

    // Critical limit analysis (only tokens and cost - messages are informational)
    private var criticalLimit: Double {
        max(tokenPercentage, costPercentage)
    }

    private var criticalMetrics: (type: String, icon: String, current: String, max: String) {
        if criticalLimit == tokenPercentage {
            return ("Tokens", "number", formatTokens(currentTokens), formatTokens(tokenLimit))
        } else {
            return ("Cost", "dollarsign.circle", CostEstimator.formatUSD(currentCost), CostEstimator.formatUSD(costLimit))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Always show regardless of plan
            let plan = viewModel.settings?.claudePlan ?? .free
            let shouldShowAlert = plan != .free && criticalLimit >= 90
            let viewMode = viewModel.settings?.claudeViewMode ?? .compact
            let showExpanded = (viewMode == .expanded) || isExpanded || (shouldAutoExpand && shouldShowAlert)

                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        // Header with plan info and billing block (always visible)
                        VStack(alignment: .leading, spacing: 3) {
                            // Plan and billing block header
                            HStack {
                                Label("Claude Code", systemImage: "bolt.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.purple)

                                Spacer()

                                // Plan selector/info - clickable button for all plans
                                Button(action: {
                                    viewModel.openPreferences()
                                }) {
                                    HStack(spacing: 4) {
                                        if plan == .free {
                                            Image(systemName: "arrow.up.circle.fill")
                                                .font(.system(size: 10))
                                            Text("Select Plan")
                                                .font(.caption)
                                        } else {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.green)
                                            Text(plan.displayName)
                                                .font(.caption)
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8))
                                    }
                                    .foregroundStyle(plan == .free ? .blue : .primary)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Click to open Preferences and \(plan == .free ? "select" : "change") your plan")

                                // Alert icon if approaching limits
                                if shouldShowAlert {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(criticalLimit >= 95 ? .red : .orange)
                                        .help("Approaching limit: \(Int(criticalLimit))%")
                                }

                                // Toggle button (only for paid plans)
                                if plan != .free {
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            if viewModel.settings?.claudeViewMode == .compact {
                                                viewModel.settings?.claudeViewMode = .expanded
                                            } else {
                                                viewModel.settings?.claudeViewMode = .compact
                                            }
                                            viewModel.settings?.saveToDisk()
                                        }
                                    }) {
                                        Image(systemName: showExpanded ? "chevron.up" : "chevron.down")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .help(showExpanded ? "Collapse view" : "Expand view")
                                }
                            }

                            // Billing block info (always visible for paid plans)
                            if plan != .free {
                                if let session = viewModel.activeClaudeSession,
                                   let block = session.currentBlock {
                                    HStack {
                                        // Block indicator with time remaining
                                        HStack(spacing: 4) {
                                            Image(systemName: "clock.fill")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.blue)
                                            Text("Block \(session.blockNumber)/\(session.totalBlocks)")
                                                .font(.system(size: 10, weight: .medium))

                                            if block.isActive {
                                                let remaining = block.endTime.timeIntervalSince(Date())
                                                if remaining > 0 {
                                                    Text("(\(formatTimeRemaining(remaining)))")
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(.green)
                                                }
                                            }
                                        }

                                        Spacer()

                                        // Block cost
                                        Text(CostEstimator.formatUSD(block.costUSD))
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    .help("5-hour billing block: \(formatDate(block.startTime)) - \(formatDate(block.endTime))")
                                } else if viewModel.activeClaudeSession == nil {
                                    // Show monthly usage when no active session
                                    HStack {
                                        Text("Monthly Usage")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(formatTokens(currentTokens)) • \(CostEstimator.formatUSD(currentCost))")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        // Show content based on plan
                        if plan == .free {
                            // Free plan message
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Usage tracking requires a paid plan")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text("Select a plan to see token usage, costs, and billing blocks")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        } else if showExpanded {
                            // Expanded view - show all progress bars
                            VStack(spacing: 8) {
                                // Token usage bar
                                UsageProgressBar(
                                    label: "Tokens",
                                    icon: "number",
                                    current: currentTokens,
                                    limit: viewModel.activeClaudeSession?.currentBlock != nil ?
                                           (viewModel.maxTokensFromPreviousBlocks ?? 10_000_000) : tokenLimit,
                                    percentage: tokenPercentage,
                                    formatter: formatTokens
                                )
                                .help(viewModel.activeClaudeSession?.currentBlock != nil ?
                                      "Current block vs personal max (\(formatTokens(viewModel.maxTokensFromPreviousBlocks ?? 10_000_000)))" :
                                      "Monthly usage vs plan limit")

                                // Cost usage bar
                                UsageProgressBar(
                                    label: "Cost",
                                    icon: "dollarsign.circle",
                                    currentText: CostEstimator.formatUSD(currentCost),
                                    limitText: viewModel.activeClaudeSession?.currentBlock != nil ?
                                              "$140.00" : CostEstimator.formatUSD(costLimit),
                                    percentage: costPercentage
                                )
                                .help(viewModel.activeClaudeSession?.currentBlock != nil ?
                                      "Current block cost vs $140 baseline" :
                                      "Monthly cost vs plan limit")

                                // Message count display
                                HStack {
                                    Label("Messages", systemImage: "message")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 70, alignment: .leading)

                                    Spacer()

                                    // Show different message text based on context
                                    if let blockMessages = messagesInBlock {
                                        Text("\(blockMessages) in block")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("\(currentMessages) this month")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } else if plan != .free {
                            // Compact view - show only the most critical limit
                            HStack(spacing: 8) {
                                Image(systemName: criticalMetrics.icon)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)

                                Text(criticalMetrics.type)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)

                                // Progress bar
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.gray.opacity(0.2))
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(progressBarColor(criticalLimit))
                                            .frame(width: geo.size.width * min(1.0, criticalLimit / 100.0))
                                    }
                                }
                                .frame(height: 4)

                                Text("\(criticalMetrics.current)/\(criticalMetrics.max)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(progressBarColor(criticalLimit))

                                Text("\(Int(criticalLimit))%")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(progressBarColor(criticalLimit))
                                    .frame(width: 35, alignment: .trailing)
                            }

                            // Brief burn rate info in compact mode
                            if let activeSession = viewModel.activeClaudeSession {
                                let sessionDuration = activeSession.lastActivity.timeIntervalSince(activeSession.startTime)
                                let hoursElapsed = sessionDuration / 3600.0

                                if hoursElapsed >= 0.017 { // At least 1 minute
                                    HStack {
                                        Image(systemName: "flame")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.orange.opacity(0.8))

                                        // Calculate time remaining based on the critical limit
                                        let burnRateInfo = calculateBurnRate(
                                            session: activeSession,
                                            criticalType: criticalMetrics.type,
                                            currentValue: criticalMetrics.type == "Tokens" ? Double(currentTokens) : currentCost,
                                            limitValue: criticalMetrics.type == "Tokens" ? Double(tokenLimit) : costLimit
                                        )

                                        Text(burnRateInfo)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)

                                        Spacer()
                                    }
                                    .padding(.top, 2)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .padding(.vertical, 4)

                // Show burn rate and detailed block progress in expanded mode
                if showExpanded && plan != .free {
                    // Block progress bar (only if there's an active session)
                    if let session = viewModel.activeClaudeSession,
                       let block = session.currentBlock {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.2))

                                let elapsed = Date().timeIntervalSince(block.startTime)
                                let duration = block.endTime.timeIntervalSince(block.startTime)
                                let progress = min(1.0, max(0.0, elapsed / duration))

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(block.isActive ? Color.blue : Color.gray)
                                    .frame(width: geo.size.width * CGFloat(progress))
                            }
                        }
                        .frame(height: 3)
                        .help("5-hour billing block progress")
                        .padding(.vertical, 2)
                    }
                }

                Divider()
        }
        .onAppear {
            // Check if we should auto-expand on appear
            shouldAutoExpand = criticalLimit >= 90
        }
    }

    private func formatTokens(_ t: Int) -> String {
        if t >= 1_000_000 {
            return String(format: "%.1fM", Double(t) / 1_000_000)
        } else if t >= 10_000 {
            return String(format: "%.0fK", Double(t) / 1_000)
        } else if t >= 1_000 {
            return String(format: "%.1fK", Double(t) / 1_000)
        } else {
            return "\(t)"
        }
    }

    private func progressBarColor(_ percentage: Double) -> Color {
        if percentage >= 90 { return .red }
        if percentage >= 70 { return .orange }
        return .green
    }

    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        } else if minutes > 0 {
            return "\(minutes)m remaining"
        } else {
            return "< 1m remaining"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func calculateBurnRate(session: ActiveSessionData, criticalType: String, currentValue: Double, limitValue: Double) -> String {
        let remaining = max(0, limitValue - currentValue)

        let rate: Double
        switch criticalType {
        case "Tokens":
            rate = session.tokensPerHour
        case "Cost":
            rate = session.costPerHour
        default:
            return "Unknown"
        }

        guard rate > 0 else { return "No burn rate" }

        let hoursRemaining = remaining / rate

        if hoursRemaining < 1 {
            let minutes = Int(hoursRemaining * 60)
            return "~\(minutes) min remaining"
        } else if hoursRemaining < 24 {
            return String(format: "~%.0f hrs remaining", hoursRemaining)
        } else {
            let days = Int(hoursRemaining / 24)
            return "~\(days) days remaining"
        }
    }
}

// Reusable progress bar component
struct UsageProgressBar: View {
    let label: String
    let icon: String
    var current: Int? = nil
    var limit: Int? = nil
    var currentText: String? = nil
    var limitText: String? = nil
    let percentage: Double
    var formatter: ((Int) -> String)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)

                Spacer()

                if let currentText = currentText, let limitText = limitText {
                    Text("\(currentText) / \(limitText)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(progressColor)
                } else if let current = current, let limit = limit, let formatter = formatter {
                    Text("\(formatter(current)) / \(formatter(limit))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(progressColor)
                }

                Text("\(Int(percentage))%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(progressColor)
                    .frame(width: 35, alignment: .trailing)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(progressColor)
                        .frame(width: geo.size.width * min(1.0, percentage / 100.0))
                }
            }
            .frame(height: 4)
        }
    }

    private var progressColor: Color {
        if percentage >= 90 { return .red }
        if percentage >= 70 { return .orange }
        return .green
    }
}

struct DropdownView_Previews: PreviewProvider {
    static var previews: some View {
        DropdownView(viewModel: .preview)
            .frame(width: 320, height: 360)
    }
}