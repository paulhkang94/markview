#!/usr/bin/env swift
import Cocoa

// Generate MarkView app icon: white "M" on a blue-purple gradient rounded rect
let sizes: [(CGFloat, String)] = [
    (16, "icon_16x16"),
    (32, "icon_16x16@2x"),
    (32, "icon_32x32"),
    (64, "icon_32x32@2x"),
    (128, "icon_128x128"),
    (256, "icon_128x128@2x"),
    (256, "icon_256x256"),
    (512, "icon_256x256@2x"),
    (512, "icon_512x512"),
    (1024, "icon_512x512@2x"),
]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.22

    // Rounded rect path
    let path = CGPath(roundedRect: rect.insetBy(dx: size * 0.02, dy: size * 0.02),
                      cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                      transform: nil)

    // Gradient background (blue to purple)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.25, green: 0.47, blue: 0.85, alpha: 1.0),  // blue
        CGColor(red: 0.55, green: 0.35, blue: 0.78, alpha: 1.0),  // purple
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: size),
                               end: CGPoint(x: size, y: 0),
                               options: [])
    }
    ctx.restoreGState()

    // Draw "M" letter
    let fontSize = size * 0.55
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let str = "M" as NSString
    let textSize = str.size(withAttributes: attrs)
    let textX = (size - textSize.width) / 2
    let textY = (size - textSize.height) / 2
    str.draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)

    // Draw small markdown hash below
    let smallFontSize = size * 0.14
    let smallFont = NSFont.systemFont(ofSize: smallFontSize, weight: .medium)
    let smallAttrs: [NSAttributedString.Key: Any] = [
        .font: smallFont,
        .foregroundColor: NSColor(white: 1.0, alpha: 0.7),
    ]
    let hashStr = "#" as NSString
    let hashSize = hashStr.size(withAttributes: smallAttrs)
    let hashX = (size - hashSize.width) / 2
    let hashY = textY - hashSize.height * 0.4
    if size >= 64 {  // Only show on larger sizes
        hashStr.draw(at: NSPoint(x: hashX, y: hashY), withAttributes: smallAttrs)
    }

    image.unlockFocus()
    return image
}

// Create .iconset directory
let scriptDir = CommandLine.arguments[0].split(separator: "/").dropLast().joined(separator: "/")
let projectDir = "/" + scriptDir.split(separator: "/").dropLast().joined(separator: "/")
let iconsetDir = projectDir + "/MarkView.iconset"

let fm = FileManager.default
try? fm.removeItem(atPath: iconsetDir)
try fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for (size, name) in sizes {
    let image = drawIcon(size: size)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(name)")
        continue
    }
    let path = iconsetDir + "/\(name).png"
    try pngData.write(to: URL(fileURLWithPath: path))
    print("Generated \(name).png (\(Int(size))x\(Int(size)))")
}

// Convert to .icns
let icnsPath = projectDir + "/Sources/MarkView/Resources/AppIcon.icns"
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", "-o", icnsPath, iconsetDir]
try task.run()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("\nGenerated: \(icnsPath)")
    try? fm.removeItem(atPath: iconsetDir)
} else {
    print("iconutil failed with status \(task.terminationStatus)")
}
