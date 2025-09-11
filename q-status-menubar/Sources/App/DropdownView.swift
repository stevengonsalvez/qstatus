import SwiftUI
import AppKit
#if canImport(Charts)
import Charts
#endif
import Core

struct DropdownView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var topSort: TopSort = .tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Global header with totals
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Overall").font(.headline)
                    Spacer()
                    // Only show percentage when we have active sessions and not in group mode
                    if !(viewModel.settings?.groupByFolder ?? false), !viewModel.sessions.isEmpty, let ctx = activeSessionContextPercent() {
                        Text("\(ctx)%")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(contextPercentColor(Double(ctx) ?? 0))
                            .help("Most recent session context usage")
                    }
                }
                .font(.caption)
                
                // Global totals display with message quota
                if viewModel.globalSessions > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Sessions: \(viewModel.globalSessions) • Tokens: \(formatTokens(viewModel.globalTokens)) • Cost: \(CostEstimator.formatUSD(viewModel.globalCost))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        HStack {
                            let msgPercent = Int((Double(viewModel.messagesMonth) / 5000.0) * 100)
                            Text("Messages: \(viewModel.messagesMonth) / 5000 (\(msgPercent)%)")
                                .font(.caption)
                                .foregroundStyle(messageQuotaColor(viewModel.messagesMonth))
                                .help("Monthly message quota usage: \(msgPercent)% used")
                            Spacer()
                        }
                    }
                }
                
                HStack {
                    Text("Period Costs: Month \(CostEstimator.formatUSD(viewModel.costMonth)) • Week \(CostEstimator.formatUSD(viewModel.costWeek))")
                    Spacer()
                    Toggle("Detailed", isOn: Binding(get: { !(viewModel.settings?.compactMode ?? true) }, set: { viewModel.settings?.compactMode = !$0 }))
                        .toggleStyle(.switch)
                        .font(.caption)
                        .help("Show sparkline and footer totals")
                }
                .font(.caption)
                if showDetailed {
                    HStack {
                        Text("🔥 Burn Rate: \(Int(viewModel.globalTokensPerMinute)) tokens/min")
                        Spacer()
                        Text("💲 Cost Rate: \(CostEstimator.formatUSD(costRatePerMin())) $/min")
                    }
                    .font(.caption)
                }
            }
            
            Divider()
            
            // Recent Sessions header block with compact bars and folder names
            if !viewModel.sessions.isEmpty {
                let recentSessions = viewModel.sessions.sorted { ($0.internalRowID ?? 0) > ($1.internalRowID ?? 0) }.prefix(5)
                if !recentSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recent Sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VStack(spacing: 4) {
                            ForEach(Array(recentSessions), id: \.id) { session in
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
                        }
                    }
                    Divider()
                }
            }

            Divider()
            // Sparkline
            if showDetailed {
                UsageSparklineCombined(values: viewModel.sparkline)
                    .frame(height: 56)
                    .padding(.top, 4)
            }

            Divider()
            // Footer: Today / Week / Month with message quota
            if showDetailed {
            VStack(spacing: 8) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Today").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(formatTokens(viewModel.tokensToday)) • \(CostEstimator.formatUSD(viewModel.costToday))").font(.caption)
                    }
                    GridRow {
                        Text("Week").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(formatTokens(viewModel.tokensWeek)) • \(CostEstimator.formatUSD(viewModel.costWeek))").font(.caption)
                    }
                    GridRow {
                        Text("Month").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(formatTokens(viewModel.tokensMonth)) • \(CostEstimator.formatUSD(viewModel.costMonth))").font(.caption)
                    }
                }
                // Message quota footer line
                HStack {
                    let msgPercent = min(100, Int((Double(viewModel.messagesMonth) / 5000.0) * 100))
                    Text("Monthly Messages:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(viewModel.messagesMonth) / 5000 (\(msgPercent)%)")
                        .font(.caption)
                        .foregroundStyle(messageQuotaColor(viewModel.messagesMonth))
                }
            }
            }
            Divider()
            // Sessions list (first page)
            if !viewModel.sessions.isEmpty {
                HStack(spacing: 12) {
                    Text("Sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Group", isOn: Binding(get: { viewModel.settings?.groupByFolder ?? false }, set: { viewModel.settings?.groupByFolder = $0 }))
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
                    Button { viewModel.forceRefresh?() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh now")
                }
                TextField("Search by id or folder…", text: $viewModel.searchQuery)
                    .textFieldStyle(.roundedBorder)
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filteredSortedSessions, id: \.id) { s in
                            Button(action: { viewModel.onSelectSession?(s) }) {
                                SessionRow(session: s, categories: viewModel.sessionCategoryTokens[s.id])
                            }
                            .buttonStyle(ClickableRowButtonStyle())
                            .help("Click to view session details")
                        }
                    }
                }
                .frame(height: 200)
                HStack {
                    Spacer()
                }
                Divider()
            }
            // Bottom: Top Sessions with sorting and View All
            if !viewModel.globalTop.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
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
                    VStack(spacing: 6) {
                        // Force re-render by including topSort in the ForEach
                        let sorted = topSortedGlobalTop().prefix(5)
                        ForEach(Array(sorted.enumerated()), id: \.element.id) { index, s in
                            TopSessionRow(session: s, onSelect: { viewModel.onSelectSession?(s) })
                                .id("\(s.id)-\(topSort.rawValue)") // Unique ID per sort mode
                        }
                    }
                    HStack {
                        ViewAllButton(action: { viewModel.onOpenAll?() })
                        Spacer()
                    }
                }
                Divider()
            }
            HStack {
                Button("Preferences…") { viewModel.openPreferences() }
                Spacer()
                Button(viewModel.isPaused ? "Resume" : "Pause") { viewModel.togglePause() }
                Button("Quit") { viewModel.quit() }
            }
        }
        .padding(14)
        .frame(width: 400)
        .sheet(item: Binding(get: { viewModel.selectedSession }, set: { _ in viewModel.selectedSession = nil })) { details in
            SessionDetailView(details: details, messagesMonth: viewModel.messagesMonth)
                .frame(width: 420, height: 400)
                .padding()
        }
        .sheet(isPresented: $viewModel.showAllSheet) {
            AllSessionsSheet(viewModel: viewModel)
                .frame(width: 500, height: 520)
        }
        // Trigger reloads when filters change
        .onChange(of: viewModel.settings?.groupByFolder ?? false) { _ in viewModel.forceRefresh?() }
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
    fileprivate func formatTokens(_ t: Int) -> String { t >= 1000 ? "\(t/1000)k" : "\(t)" }
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
    
    fileprivate func messageQuotaColor(_ messages: Int) -> Color {
        let quota = 5000
        let percent = Double(messages) / Double(quota) * 100
        if percent >= 90 { return .red }
        if percent >= 75 { return .orange }
        if percent >= 50 { return .yellow }
        return .secondary
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
                    let msgPercent = min(100, Int((Double(messagesMonth) / 5000.0) * 100))
                    Text("Monthly Messages:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(messagesMonth) / 5000 (\(msgPercent)%)")
                        .font(.caption)
                        .foregroundStyle(messageQuotaColor(messagesMonth))
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
        let quota = 5000
        let percent = Double(messages) / Double(quota) * 100
        if percent >= 90 { return .red }
        if percent >= 75 { return .orange }
        if percent >= 50 { return .yellow }
        return .secondary
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
                // Message quota footer line
                HStack {
                    let msgPercent = min(100, Int((Double(viewModel.messagesMonth) / 5000.0) * 100))
                    Text("Monthly Messages:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(viewModel.messagesMonth) / 5000 (\(msgPercent)%)")
                        .font(.caption)
                        .foregroundStyle(messageQuotaColor(viewModel.messagesMonth))
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
        let quota = 5000
        let percent = Double(messages) / Double(quota) * 100
        if percent >= 90 { return .red }
        if percent >= 75 { return .orange }
        if percent >= 50 { return .yellow }
        return .secondary
    }
}

struct DropdownView_Previews: PreviewProvider {
    static var previews: some View {
        DropdownView(viewModel: .preview)
            .frame(width: 320, height: 360)
    }
}
