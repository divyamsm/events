#!/usr/bin/env swift

import AppKit
import CoreGraphics

// Generate compressed 1024x1024 icon
func generateCompressedIcon(outputPath: String) {
    let size: CGFloat = 1024
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // Create image
    let image = NSImage(size: rect.size)
    image.lockFocus()

    // Draw gradient background
    let gradient = NSGradient(colors: [
        NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0),  // Blue
        NSColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1.0)  // Purple
    ])
    gradient?.draw(in: rect, angle: 135)

    // Configure SF Symbol
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .semibold)

    // Try to get the SF Symbol (figure.walk for "step out")
    if let symbolImage = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {

        // Calculate centered position
        let symbolSize = symbolImage.size
        let x = (size - symbolSize.width) / 2
        let y = (size - symbolSize.height) / 2
        let symbolRect = CGRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height)

        // Draw white symbol
        symbolImage.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()

    // Save as PNG with compression
    if let tiffData = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let pngData = bitmap.representation(using: .png, properties: [.compressionFactor: 0.8]) {
        try? pngData.write(to: URL(fileURLWithPath: outputPath))

        // Check file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: outputPath),
           let fileSize = attrs[.size] as? Int {
            let sizeMB = Double(fileSize) / 1024.0 / 1024.0
            print("✅ Generated compressed icon: \(sizeMB) MB")
        }
    }
}

let outputPath = "/Users/bharath/Desktop/events/StepOut/StepOut/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
print("🎨 Generating compressed 1024x1024 icon...")
generateCompressedIcon(outputPath: outputPath)
print("✅ Done!")
