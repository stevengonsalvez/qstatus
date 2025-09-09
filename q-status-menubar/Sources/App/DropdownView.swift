import SwiftUI
import AppKit
#if canImport(Charts)
import Charts
#endif
import Core

struct DropdownView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Global header summary
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Q Token Usage").font(.headline)
                    Text(globalSummaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(viewModel.percent)%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(viewModel.tintColor)
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Label("Tokens Used", systemImage: "bolt.fill")
                    Spacer()
                    Text("\(viewModel.tokensUsed)")
                }
                GridRow {
                    Label("Remaining", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    Spacer()
                    Text("\(viewModel.tokensRemaining)")
                }
                GridRow {
                    Label("Rate", systemImage: "speedometer")
                    Spacer()
                    Text("\(Int(viewModel.tokensPerMinute)) tpm")
                }
                GridRow {
                    Label("Est. Time Left", systemImage: "clock")
                    Spacer()
                    Text(viewModel.timeRemaining)
                }
                GridRow {
                    Label("Est. Cost", systemImage: "dollarsign.circle")
                    Spacer()
                    Text(viewModel.estimatedCost)
                }
                GridRow {
                    Label("Page Cost", systemImage: "dollarsign.square")
                    Spacer()
                    Text(viewModel.pageCost)
                }
                GridRow {
                    Label("Page Sessions", systemImage: "rectangle.stack")
                    Spacer()
                    Text("\(viewModel.totalSessions) • near limit: \(viewModel.sessionsNearLimit)")
                }
                GridRow {
                    Label("Page Tokens", systemImage: "sum")
                    Spacer()
                    Text("\(viewModel.totalTokens)")
                }
                GridRow {
                    Label("All Sessions", systemImage: "tray.full")
                    Spacer()
                    Text("\(viewModel.globalSessions) • near limit: \(viewModel.globalNearLimit)")
                }
                GridRow {
                    Label("All Tokens", systemImage: "sum")
                    Spacer()
                    Text("\(viewModel.globalTokens)")
                }
            }
            .font(.subheadline)

            Divider()
            if !viewModel.globalTop.isEmpty {
                Text("Top Sessions (by tokens)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    ForEach(viewModel.globalTop, id: \.id) { s in
                        Button(action: { viewModel.onSelectSession?(s) }) {
                            HStack {
                                Text(shortId(s.id))
                                    .font(.system(.caption, design: .monospaced))
                                Spacer()
                                Text("\(formatTokens(s.tokensUsed)) • \(Int(s.usagePercent))%")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Divider()
            }
            // Sparkline
            UsageSparklineCombined(values: viewModel.sparkline)
                .frame(height: 56)
                .padding(.top, 4)

            Divider()
            // Footer: Today / Week / Month
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Today").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(viewModel.tokensToday) • \(CostEstimator.formatUSD(viewModel.costToday))").font(.caption)
                }
                GridRow {
                    Text("Week").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(viewModel.tokensWeek) • \(CostEstimator.formatUSD(viewModel.costWeek))").font(.caption)
                }
                GridRow {
                    Text("Month").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(viewModel.tokensMonth) • \(CostEstimator.formatUSD(viewModel.costMonth))").font(.caption)
                }
            }
            Divider()
            // Sessions list (first page)
            if !viewModel.sessions.isEmpty {
                HStack {
                    Text("Sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Active (7d)", isOn: Binding(get: { viewModel.settings?.showActiveLast7Days ?? false }, set: { viewModel.settings?.showActiveLast7Days = $0 }))
                        .toggleStyle(.switch)
                        .font(.caption)
                    Toggle("Group by folder", isOn: Binding(get: { viewModel.settings?.groupByFolder ?? false }, set: { viewModel.settings?.groupByFolder = $0 }))
                        .toggleStyle(.switch)
                        .font(.caption)
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
                                SessionRow(session: s)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 200)
                HStack {
                    Button("View All…") { viewModel.onOpenAll?() }
                    Spacer()
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
            SessionDetailView(details: details)
                .frame(width: 420, height: 360)
                .padding()
        }
        .sheet(isPresented: $viewModel.showAllSheet) {
            AllSessionsSheet(viewModel: viewModel)
                .frame(width: 500, height: 520)
        }
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
    fileprivate func shortId(_ id: String) -> String { id.count > 10 ? String(id.prefix(8)) + "…" : id }
    fileprivate func formatTokens(_ t: Int) -> String { t >= 1000 ? "\(t/1000)k" : "\(t)" }
}

struct SessionDetailView: View {
    let details: SessionDetails
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
            Spacer()
            HStack {
                Button("Copy ID") { copyToClipboard(details.summary.id) }
                if let cwd = details.summary.cwd { Button("Reveal in Finder") { revealInFinder(cwd) } }
                Spacer()
                Button("Close") { /* sheet dismisses on binding set to nil */ }
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
}

struct SessionRow: View {
    let session: SessionSummary
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(shortId(session.id))
                    .font(.system(.caption, design: .monospaced))
                if let cwd = session.cwd, !cwd.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(cwdTail(cwd))
                            .truncationMode(.head)
                            .help(cwd)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: min(max(session.usagePercent/100.0, 0), 1))
                    .tint(color(for: session))
                    .frame(width: 120)
                Text("\(formatTokens(session.tokensUsed)) / \(formatTokens(session.contextWindow)) • \(Int(session.usagePercent))% • \(CostEstimator.formatUSD(session.costUSD))")
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
    private func formatTokens(_ t: Int) -> String {
        if t >= 1000 { return "\(t/1000)k" } else { return "\(t)" }
    }
    private func color(for s: SessionSummary) -> Color {
        switch s.state { case .critical: return .red; case .warn: return .yellow; default: return .green }
    }
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
                        Button(action: { viewModel.onSelectSession?(s) }) { SessionRow(session: s) }
                            .buttonStyle(.plain)
                    }
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
}

struct DropdownView_Previews: PreviewProvider {
    static var previews: some View {
        DropdownView(viewModel: .preview)
            .frame(width: 320, height: 360)
    }
}
