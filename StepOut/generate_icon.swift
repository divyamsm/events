#!/usr/bin/env swift

import AppKit
import CoreGraphics

// Generate app icon with gradient background and SF Symbol
func generateAppIcon(size: CGFloat, outputPath: String) {
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

    // Save as PNG
    if let tiffData = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let pngData = bitmap.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: outputPath))
        print("✅ Generated icon: \(outputPath)")
    }
}

// Required iOS app icon sizes
let sizes: [(size: CGFloat, name: String)] = [
    (1024, "AppIcon-1024"),  // App Store
    (180, "AppIcon-180"),    // iPhone 3x
    (120, "AppIcon-120"),    // iPhone 2x
    (167, "AppIcon-167"),    // iPad Pro
    (152, "AppIcon-152"),    // iPad 2x
    (76, "AppIcon-76"),      // iPad 1x
    (60, "AppIcon-60"),      // iPhone Settings 3x
    (40, "AppIcon-40"),      // iPhone Settings 2x
    (29, "AppIcon-29"),      // iPhone Settings 1x
]

// Create output directory
let outputDir = "/Users/bharath/Desktop/events/StepOut/AppIconTemp"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

print("🎨 Generating StepOut app icons...")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

for (size, name) in sizes {
    let outputPath = "\(outputDir)/\(name).png"
    generateAppIcon(size: size, outputPath: outputPath)
}

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("✅ All icons generated successfully!")
print("📁 Icons saved to: \(outputDir)")
print("")
print("Next steps:")
print("1. Open Xcode")
print("2. Select Assets.xcassets in the Project Navigator")
print("3. Click on AppIcon")
print("4. Drag and drop the generated icons to their respective slots")
