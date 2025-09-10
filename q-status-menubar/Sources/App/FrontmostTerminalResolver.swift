import AppKit
import ApplicationServices

enum FrontmostTerminalResolver {
    static func resolveCWD() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let bid = app.bundleIdentifier ?? ""
        guard bid == "com.apple.Terminal" || bid == "com.googlecode.iterm2" || bid == "dev.warp.Warp" else { return nil }
        guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true] as CFDictionary) else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        var axApp: AXUIElement?
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &value) == .success,
           let v = value {
            axApp = (v as! AXUIElement)
        }
        guard let axApp else { return nil }
        var axWindow: AXUIElement?
        value = nil
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
           let v = value {
            axWindow = (v as! AXUIElement)
        }
        guard let axWindow else { return nil }
        // Try document attribute first (some apps expose representedURL)
        if let docTitle = copyStringAttr(axWindow, kAXDocumentAttribute as CFString),
           let path = extractPath(from: docTitle) { return path }
        // Window title next
        if let title = copyStringAttr(axWindow, kAXTitleAttribute as CFString),
           let path = extractPath(from: title) { return path }
        // Some apps nest title in a title UI element
        if let titleUI = copyElementAttr(axWindow, kAXTitleUIElementAttribute as CFString),
           let t = copyStringAttr(titleUI, kAXValueAttribute as CFString),
           let path = extractPath(from: t) { return path }
        // As a last resort, scan immediate children for text values
        if let children = copyArrayAttr(axWindow, kAXChildrenAttribute as CFString) as? [AXUIElement] {
            for child in children {
                if let t = copyStringAttr(child, kAXTitleAttribute as CFString), let p = extractPath(from: t) { return p }
                if let v = copyStringAttr(child, kAXValueAttribute as CFString), let p = extractPath(from: v) { return p }
            }
        }
        return nil
    }

    private static func extractPath(from title: String) -> String? {
        // Match /Users/... or ~/... patterns
        let patterns = [#"(/[^\s:]+)+"#, #"~(/[^\s:]+)*"#]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: []) {
                let range = NSRange(title.startIndex..<title.endIndex, in: title)
                if let match = regex.firstMatch(in: title, options: [], range: range) {
                    if let r = Range(match.range, in: title) {
                        let raw = String(title[r])
                        let expanded = (raw as NSString).expandingTildeInPath
                        // Ensure it is a directory path
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                            return expanded
                        }
                        // If not a directory, return parent
                        return (expanded as NSString).deletingLastPathComponent
                    }
                }
            }
        }
        return nil
    }
}

// MARK: - AX helpers
private func copyStringAttr(_ element: AXUIElement, _ attr: CFString) -> String? {
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, attr, &value) == .success, let v = value, CFGetTypeID(v) == CFStringGetTypeID() {
        return (v as! CFString) as String
    }
    return nil
}
private func copyElementAttr(_ element: AXUIElement, _ attr: CFString) -> AXUIElement? {
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, attr, &value) == .success, let v = value {
        return (v as! AXUIElement)
    }
    return nil
}
private func copyArrayAttr(_ element: AXUIElement, _ attr: CFString) -> CFArray? {
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, attr, &value) == .success, let v = value, CFGetTypeID(v) == CFArrayGetTypeID() {
        return (v as! CFArray)
    }
    return nil
}
