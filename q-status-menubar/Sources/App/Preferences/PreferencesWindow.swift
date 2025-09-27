import SwiftUI
import Core

struct PreferencesWindow: View {
    @StateObject private var settings = SettingsStore()

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            MenubarTab(settings: settings)
                .tabItem { Label("Menubar", systemImage: "menubar.rectangle") }
            NotificationsTab(settings: settings)
                .tabItem { Label("Notifications", systemImage: "bell") }
            AppearanceTab(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            AdvancedTab(settings: settings)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .padding()
        .frame(width: 550, height: 480)
        .onChange(of: settings.updateInterval) { _ in settings.saveToDisk() }
        .onChange(of: settings.showPercentBadge) { _ in settings.saveToDisk() }
        .onChange(of: settings.launchAtLogin) { newValue in
            settings.saveToDisk()
            LaunchAtLoginHelper.setEnabled(newValue)
        }
        .onChange(of: settings.notificationsEnabled) { _ in settings.saveToDisk() }
        .onChange(of: settings.warnThreshold) { _ in settings.saveToDisk() }
        .onChange(of: settings.highThreshold) { _ in settings.saveToDisk() }
        .onChange(of: settings.criticalThreshold) { _ in settings.saveToDisk() }
        .onChange(of: settings.colorScheme) { _ in settings.saveToDisk() }
        .onChange(of: settings.sessionTokenLimit) { _ in settings.saveToDisk() }
        .onChange(of: settings.iconMode) { _ in settings.saveToDisk() }
        .onChange(of: settings.pinnedSessionKey) { _ in settings.saveToDisk() }
        .onChange(of: settings.showActiveBadge) { _ in settings.saveToDisk() }
        .onChange(of: settings.compactMode) { _ in settings.saveToDisk() }
        .onChange(of: settings.defaultContextWindowTokens) { _ in settings.saveToDisk() }
        .onChange(of: settings.costRatePer1kTokensUSD) { _ in settings.saveToDisk() }
        .onChange(of: settings.dataSourceType) { _ in settings.saveToDisk() }
        .onChange(of: settings.claudeConfigPaths) { _ in settings.saveToDisk() }
        .onChange(of: settings.costMode) { _ in settings.saveToDisk() }
        .onChange(of: settings.claudePlan) { _ in settings.saveToDisk() }
        .onChange(of: settings.customPlanP90Percentile) { _ in settings.saveToDisk() }
        .onChange(of: settings.customPlanUseP90) { _ in settings.saveToDisk() }
        .onChange(of: settings.customPlanTokenLimit) { _ in settings.saveToDisk() }
        .onChange(of: settings.customPlanCostLimit) { _ in settings.saveToDisk() }
        .onChange(of: settings.customPlanMessageLimit) { _ in settings.saveToDisk() }
    }
}

private struct GeneralTab: View {
    @ObservedObject var settings: SettingsStore
    @State private var showRestartAlert = false

    // Helper functions for plan limits
    private func getCurrentTokenLimit() -> Int {
        if settings.claudePlan == .custom {
            return settings.customPlanUseP90 ? settings.customPlanTokenLimit : settings.customPlanTokenLimit
        }
        return settings.claudePlan.tokenLimit
    }

    private func getCurrentCostLimit() -> Double {
        if settings.claudePlan == .custom {
            return settings.customPlanUseP90 ? settings.customPlanCostLimit : settings.customPlanCostLimit
        }
        return settings.claudePlan.costLimit
    }

    private func getCurrentMessageLimit() -> Int {
        if settings.claudePlan == .custom {
            return settings.customPlanUseP90 ? settings.customPlanMessageLimit : settings.customPlanMessageLimit
        }
        return settings.claudePlan.messageLimit
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func currencyFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }

    var body: some View {
        Form {
            Section(header: Text("Data Source")) {
                Picker("Provider", selection: $settings.dataSourceType) {
                    ForEach(DataSourceType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.dataSourceType) { _ in
                    showRestartAlert = true
                }

                if settings.dataSourceType == .claudeCode {
                    // Claude Plan Selection
                    Picker("Plan", selection: $settings.claudePlan) {
                        ForEach(ClaudePlan.allCases, id: \.self) { plan in
                            Text(plan.displayName).tag(plan)
                        }
                    }
                    .pickerStyle(.menu)

                    // Display plan details
                    GroupBox(label: Text("Plan Limits").font(.caption).foregroundStyle(.secondary)) {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tokens:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if settings.claudePlan == .custom && !settings.customPlanUseP90 {
                                    Text(formatNumber(settings.customPlanTokenLimit))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                } else {
                                    Text(formatNumber(getCurrentTokenLimit()))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                            }

                            Divider()
                                .frame(height: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cost:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if settings.claudePlan == .custom && !settings.customPlanUseP90 {
                                    Text("$\(String(format: "%.0f", settings.customPlanCostLimit))/mo")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                } else {
                                    Text("$\(String(format: "%.0f", getCurrentCostLimit()))/mo")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                            }

                            Divider()
                                .frame(height: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Messages:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if settings.claudePlan == .custom && !settings.customPlanUseP90 {
                                    Text(formatNumber(settings.customPlanMessageLimit))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                } else {
                                    Text(formatNumber(getCurrentMessageLimit()))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }

                    // Custom Plan Configuration (only show when Custom is selected)
                    if settings.claudePlan == .custom {
                        GroupBox(label: Text("Custom Plan Configuration").font(.caption)) {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Use P90 calculation", isOn: $settings.customPlanUseP90)
                                    .font(.caption)

                                if settings.customPlanUseP90 {
                                    // P90 Percentile Slider
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("P90 Percentile:")
                                                .font(.caption)
                                            Spacer()
                                            Text("\(Int(settings.customPlanP90Percentile))%")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Slider(value: $settings.customPlanP90Percentile, in: 50...99, step: 1)
                                    }
                                } else {
                                    // Manual limit inputs
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Token Limit:")
                                                .font(.caption)
                                                .frame(width: 90, alignment: .leading)
                                            TextField("200000", value: $settings.customPlanTokenLimit, formatter: NumberFormatter())
                                                .textFieldStyle(.roundedBorder)
                                                .font(.caption)
                                        }

                                        HStack {
                                            Text("Cost Limit:")
                                                .font(.caption)
                                                .frame(width: 90, alignment: .leading)
                                            HStack(spacing: 2) {
                                                Text("$").font(.caption).foregroundStyle(.secondary)
                                                TextField("100.00", value: $settings.customPlanCostLimit, formatter: currencyFormatter())
                                                    .textFieldStyle(.roundedBorder)
                                                    .font(.caption)
                                            }
                                        }

                                        HStack {
                                            Text("Message Limit:")
                                                .font(.caption)
                                                .frame(width: 90, alignment: .leading)
                                            TextField("10000", value: $settings.customPlanMessageLimit, formatter: NumberFormatter())
                                                .textFieldStyle(.roundedBorder)
                                                .font(.caption)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                    }

                    // Configuration paths
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Claude configuration paths (one per line):")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: Binding(
                            get: { settings.claudeConfigPaths.joined(separator: "\n") },
                            set: { settings.claudeConfigPaths = $0.split(separator: "\n").map(String.init) }
                        ))
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 60)
                    }

                    Picker("Cost Mode", selection: $settings.costMode) {
                        Text("Auto").tag("auto")
                        Text("Input").tag("input")
                        Text("Output").tag("output")
                        Text("Cache Read").tag("cache_read")
                        Text("Cache Write").tag("cache_write")
                    }
                }
            }

            Section(header: Text("General")) {
                Stepper(value: $settings.updateInterval, in: 1...30) {
                    HStack { Text("Polling Interval"); Spacer(); Text("\(settings.updateInterval)s") }
                }
                Toggle("Show Percentage Badge", isOn: $settings.showPercentBadge)
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            }
        }
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("OK") { }
        } message: {
            Text("Please restart the app for the data source change to take effect.")
        }
    }
}

private struct MenubarTab: View {
    @ObservedObject var settings: SettingsStore
    @State private var pinInput: String = ""
    var body: some View {
        Form {
            Picker("Icon Mode", selection: $settings.iconMode) {
                Text("Most‑Recent Session").tag(SettingsStore.IconMode.mostRecent)
                Text("Pinned Session").tag(SettingsStore.IconMode.pinned)
                Text("Frontmost Terminal").tag(SettingsStore.IconMode.frontmostTerminal)
                Text("Monthly Messages").tag(SettingsStore.IconMode.monthlyMessages)
            }
            .pickerStyle(.segmented)
            Toggle("Badge when multiple sessions active", isOn: $settings.showActiveBadge)
            Toggle("Compact dropdown by default", isOn: $settings.compactMode)
            if settings.iconMode == .pinned {
                TextField("Pinned session ID or folder path", text: Binding(get: { settings.pinnedSessionKey ?? "" }, set: { settings.pinnedSessionKey = $0.isEmpty ? nil : $0 }))
                    .textFieldStyle(.roundedBorder)
                    .help("Provide a conversation key or an absolute folder path to pin.")
            }
            if settings.iconMode == .frontmostTerminal {
                Text("Frontmost Terminal integration requires Accessibility permission (planned). Falling back to Most‑Recent for now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NotificationsTab: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        Form {
            Toggle("Enable Notifications", isOn: $settings.notificationsEnabled)
            HStack {
                Text("Thresholds")
                Spacer()
                Text("\(settings.warnThreshold)% / \(settings.highThreshold)% / \(settings.criticalThreshold)%")
            }
        }
    }
}

private struct AppearanceTab: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        Form {
            Picker("Color Scheme", selection: $settings.colorScheme) {
                Text("Auto").tag(SettingsStore.ColorScheme.auto)
                Text("Light").tag(SettingsStore.ColorScheme.light)
                Text("Dark").tag(SettingsStore.ColorScheme.dark)
            }
        }
    }
}

private struct AdvancedTab: View {
    @ObservedObject var settings: SettingsStore
    @State private var contextWindowText: String = ""
    @State private var costRateText: String = ""
    
    private let tokenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 1000
        formatter.maximum = 1000000
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter
    }()
    
    private let costFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 4
        formatter.maximumFractionDigits = 4
        formatter.minimum = 0.0001
        formatter.maximum = 1.0
        return formatter
    }()
    
    var body: some View {
        Form {
            Section(header: Text("Token Limits")) {
                HStack {
                    Text("Default Context Window")
                    Spacer()
                    TextField("Tokens", value: $settings.defaultContextWindowTokens, formatter: tokenFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Text("tokens")
                        .foregroundStyle(.secondary)
                }
                .help("Default context window size when not specified by the model (default: 175,000)")
                
                HStack {
                    Text("Session Warning Limit")
                    Spacer()
                    TextField("Tokens", value: $settings.sessionTokenLimit, formatter: tokenFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Text("tokens")
                        .foregroundStyle(.secondary)
                }
                .help("Token limit for session health warnings (default: 44,000)")
            }
            
            Section(header: Text("Cost Estimation")) {
                HStack {
                    Text("Cost per 1K Tokens")
                    Spacer()
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("0.0066", value: $settings.costRatePer1kTokensUSD, formatter: costFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("USD")
                        .foregroundStyle(.secondary)
                }
                .help("Cost per 1,000 tokens in USD (default: $0.0066)")
                
                HStack {
                    Text("Model Name")
                    Spacer()
                    TextField("Model", text: $settings.costModelName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
                .help("Name of the cost model for display purposes")
            }
            
            Text("These settings apply to new sessions and calculations")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct PreferencesWindow_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesWindow()
    }
}
