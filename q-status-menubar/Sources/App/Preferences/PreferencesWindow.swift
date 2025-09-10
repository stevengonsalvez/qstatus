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
        }
        .padding()
        .frame(width: 520, height: 380)
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
    }
}

private struct GeneralTab: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        Form {
            Stepper(value: $settings.updateInterval, in: 1...30) {
                HStack { Text("Polling Interval"); Spacer(); Text("\(settings.updateInterval)s") }
            }
            Toggle("Show Percentage Badge", isOn: $settings.showPercentBadge)
            Toggle("Launch at Login", isOn: $settings.launchAtLogin)
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

struct PreferencesWindow_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesWindow()
    }
}
