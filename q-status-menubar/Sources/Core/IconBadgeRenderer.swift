import AppKit

public enum IconBadgeRenderer {
    public static func render(percentage: Int, state: HealthState) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()

        let bgColor: NSColor = {
            switch state {
            case .idle: return .disabledControlTextColor
            case .healthy: return NSColor.systemGreen
            case .warning: return NSColor.systemYellow
            case .critical: return NSColor.systemRed
            }
        }()

        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        bgColor.setFill()
        path.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.boldSystemFont(ofSize: 11)
        ]
        let text = "\(percentage)%" as NSString
        let textSize = text.size(withAttributes: attrs)
        let point = NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2)
        text.draw(at: point, withAttributes: attrs)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

