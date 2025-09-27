// ABOUTME: Factory for creating data sources based on provider type
// Supports switching between Amazon Q and Claude Code data sources

import Foundation

public enum DataSourceType: String, CaseIterable, Codable {
    case amazonQ = "amazon-q"
    case claudeCode = "claude-code"

    public var displayName: String {
        switch self {
        case .amazonQ: return "Amazon Q"
        case .claudeCode: return "Claude Code"
        }
    }

    public var iconName: String {
        switch self {
        case .amazonQ: return "q.circle"
        case .claudeCode: return "c.circle"
        }
    }
}

public struct DataSourceFactory {
    public static func create(type: DataSourceType, settings: SettingsStore) -> any DataSource {
        switch type {
        case .amazonQ:
            return QDBReader(defaultContextWindow: settings.defaultContextWindowTokens)
        case .claudeCode:
            return ClaudeCodeDataSource(
                configPaths: settings.claudeConfigPaths,
                costMode: CostMode(rawValue: settings.costMode) ?? .auto
            )
        }
    }
}