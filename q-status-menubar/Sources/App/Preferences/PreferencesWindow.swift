import SwiftUI
import Core

struct PreferencesWindow: View {
    @StateObject private var settings = SettingsStore()

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
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
