import AppKit

public enum IconBadgeRenderer {
    public static func render(percentage: Int, state: HealthState, badge: Int? = nil, labelOverride: String? = nil) -> NSImage {
        // Increased width from 22 to 36 to accommodate "100%" without cutoff
        let size = NSSize(width: 36, height: 22)
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
        let text = (labelOverride ?? "\(percentage)%") as NSString
        let textSize = text.size(withAttributes: attrs)
        let point = NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2)
        text.draw(at: point, withAttributes: attrs)

        if let badge, badge > 1 {
            // Draw a small circular badge at top-right with count
            let badgeSize: CGFloat = 10
            let badgeRect = NSRect(x: size.width - badgeSize - 1, y: size.height - badgeSize - 1, width: badgeSize, height: badgeSize)
            let badgePath = NSBezierPath(ovalIn: badgeRect)
            NSColor.systemIndigo.setFill()
            badgePath.fill()
            let bAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.boldSystemFont(ofSize: 7)
            ]
            let bText = (badge > 9 ? "9+" : "\(badge)") as NSString
            let bSize = bText.size(withAttributes: bAttrs)
            let bPoint = NSPoint(x: badgeRect.midX - bSize.width/2, y: badgeRect.midY - bSize.height/2)
            bText.draw(at: bPoint, withAttributes: bAttrs)
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
