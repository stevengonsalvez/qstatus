#!/usr/bin/env swift
// ABOUTME: Creates an app icon for QStatus
import Cocoa
import CoreGraphics

// Create icon at different sizes
let sizes = [16, 32, 64, 128, 256, 512, 1024]

// Create icon directory
let iconsetPath = "QStatus.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for size in sizes {
    // Create both @1x and @2x versions
    for scale in [1, 2] {
        let actualSize = scale == 1 ? size : size * 2
        let filename = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        
        // Create image
        let image = NSImage(size: NSSize(width: actualSize, height: actualSize))
        image.lockFocus()
        
        // Background gradient
        let gradient = NSGradient(colors: [
            NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0),
            NSColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1.0)
        ])!
        
        let rect = NSRect(x: 0, y: 0, width: actualSize, height: actualSize)
        let path = NSBezierPath(roundedRect: rect, xRadius: CGFloat(actualSize) * 0.22, yRadius: CGFloat(actualSize) * 0.22)
        gradient.draw(in: path, angle: -90)
        
        // Draw "Q" letter
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: CGFloat(actualSize) * 0.5, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        
        let text = "Q"
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: (CGFloat(actualSize) - textSize.width) / 2,
            y: (CGFloat(actualSize) - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
        
        image.unlockFocus()
        
        // Save as PNG
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: "\(iconsetPath)/\(filename)")
            try? pngData.write(to: url)
            print("Created \(filename)")
        }
    }
}

print("Icon set created at \(iconsetPath)")
print("Run: iconutil -c icns \(iconsetPath) to create the .icns file")