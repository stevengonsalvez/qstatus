import Foundation
#if canImport(ServiceManagement)
import ServiceManagement
#endif

public enum LaunchAtLoginHelper {
    public static func setEnabled(_ enabled: Bool) {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    SMAppService.mainApp.unregister()
                }
            } catch {
                // Ignore in dev context; this requires app bundle
            }
        }
        #endif
    }
}

