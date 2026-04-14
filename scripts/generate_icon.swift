#!/usr/bin/swift

import AppKit
import Foundation

// MARK: - Configuration

let projectDir = FileManager.default.currentDirectoryPath
let resourcesDir = "\(projectDir)/Resources"
let iconsetDir = "\(resourcesDir)/AppIcon.iconset"
let icnsPath = "\(resourcesDir)/AppIcon.icns"

// MARK: - Helper: draw into an NSImage of a given size

func makeAppIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.22 // Big Sur style

    // --- Rounded-rect background with gradient ---
    let path = CGPath(roundedRect: rect.insetBy(dx: size * 0.01, dy: size * 0.01),
                      cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                      transform: nil)
    ctx.addPath(path)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.20, green: 0.40, blue: 0.95, alpha: 1.0), // blue
        CGColor(red: 0.45, green: 0.20, blue: 0.85, alpha: 1.0), // indigo/purple
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: size),
                               end: CGPoint(x: size, y: 0),
                               options: [])
    }

    // Subtle inner shadow / vignette overlay
    let overlayColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.12),
        CGColor(red: 0, green: 0, blue: 0, alpha: 0.10),
    ] as CFArray
    if let overlay = CGGradient(colorsSpace: colorSpace, colors: overlayColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(overlay,
                               start: CGPoint(x: size / 2, y: size),
                               end: CGPoint(x: size / 2, y: 0),
                               options: [])
    }

    // --- Draw "EN" (top-left area) ---
    let bigFontSize = size * 0.22
    let smallFontSize = size * 0.22
    let textColor = NSColor.white

    let enAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: bigFontSize, weight: .bold),
        .foregroundColor: textColor,
    ]
    let ruAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: smallFontSize, weight: .bold),
        .foregroundColor: textColor,
    ]

    let enStr = NSAttributedString(string: "EN", attributes: enAttrs)
    let ruStr = NSAttributedString(string: "RU", attributes: ruAttrs)

    let enSize = enStr.size()
    let ruSize = ruStr.size()

    let padding = size * 0.12

    // EN top-left
    enStr.draw(at: NSPoint(x: padding, y: size - padding - enSize.height))

    // RU bottom-right
    ruStr.draw(at: NSPoint(x: size - padding - ruSize.width, y: padding))

    // --- Draw swap arrows (two curved arrows forming a cycle) ---
    drawSwapArrows(ctx: ctx, size: size)

    image.unlockFocus()
    return image
}

func drawSwapArrows(ctx: CGContext, size: CGFloat) {
    let cx = size * 0.5
    let cy = size * 0.5
    let radius = size * 0.16
    let arrowLineWidth = size * 0.035
    let arrowHeadLength = size * 0.06

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.setLineWidth(arrowLineWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Arrow 1: top-right arc (from ~30deg to ~170deg)
    let startAngle1: CGFloat = .pi * 0.15
    let endAngle1: CGFloat = .pi * 0.85
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: radius,
               startAngle: startAngle1, endAngle: endAngle1, clockwise: false)
    ctx.strokePath()

    // Arrowhead at end of arc 1
    let tipX1 = cx + radius * cos(endAngle1)
    let tipY1 = cy + radius * sin(endAngle1)
    drawArrowhead(ctx: ctx, tipX: tipX1, tipY: tipY1,
                  angle: endAngle1 + .pi / 2, // perpendicular to radius = tangent direction
                  length: arrowHeadLength, lineWidth: arrowLineWidth)

    // Arrow 2: bottom-left arc (from ~210deg to ~350deg)
    let startAngle2: CGFloat = .pi * 1.15
    let endAngle2: CGFloat = .pi * 1.85
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: radius,
               startAngle: startAngle2, endAngle: endAngle2, clockwise: false)
    ctx.strokePath()

    // Arrowhead at end of arc 2
    let tipX2 = cx + radius * cos(endAngle2)
    let tipY2 = cy + radius * sin(endAngle2)
    drawArrowhead(ctx: ctx, tipX: tipX2, tipY: tipY2,
                  angle: endAngle2 + .pi / 2,
                  length: arrowHeadLength, lineWidth: arrowLineWidth)
}

func drawArrowhead(ctx: CGContext, tipX: CGFloat, tipY: CGFloat,
                   angle: CGFloat, length: CGFloat, lineWidth: CGFloat) {
    let spread: CGFloat = .pi / 5
    let x1 = tipX - length * cos(angle - spread)
    let y1 = tipY - length * sin(angle - spread)
    let x2 = tipX - length * cos(angle + spread)
    let y2 = tipY - length * sin(angle + spread)

    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.move(to: CGPoint(x: tipX, y: tipY))
    ctx.addLine(to: CGPoint(x: x1, y: y1))
    ctx.addLine(to: CGPoint(x: x2, y: y2))
    ctx.closePath()
    ctx.fillPath()
}

// MARK: - Helper: save NSImage as PNG

func savePNG(_ image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("ERROR: Failed to create PNG for \(path)")
        return
    }
    do {
        try pngData.write(to: URL(fileURLWithPath: path))
    } catch {
        print("ERROR: Failed to write \(path): \(error)")
    }
}

// MARK: - Helper: create image at exact pixel dimensions (for @2x support)

func makeAppIconPixels(pixelWidth: Int) -> NSImage {
    let size = CGFloat(pixelWidth)
    return makeAppIcon(size: size)
}

// MARK: - Generate .iconset

func generateIconset() {
    // Create iconset directory
    try? FileManager.default.removeItem(atPath: iconsetDir)
    try! FileManager.default.createDirectory(atPath: iconsetDir,
                                              withIntermediateDirectories: true)

    // Required sizes: pairs of (point size, scale)
    let specs: [(name: String, pointSize: Int, scale: Int)] = [
        ("icon_16x16",      16,  1),
        ("icon_16x16@2x",   16,  2),
        ("icon_32x32",      32,  1),
        ("icon_32x32@2x",   32,  2),
        ("icon_128x128",    128, 1),
        ("icon_128x128@2x", 128, 2),
        ("icon_256x256",    256, 1),
        ("icon_256x256@2x", 256, 2),
        ("icon_512x512",    512, 1),
        ("icon_512x512@2x", 512, 2),
    ]

    for spec in specs {
        let pixelSize = spec.pointSize * spec.scale
        let image = makeAppIconPixels(pixelWidth: pixelSize)
        let path = "\(iconsetDir)/\(spec.name).png"
        savePNG(image, to: path)
        print("  Created \(spec.name).png (\(pixelSize)x\(pixelSize) px)")
    }
}

// MARK: - Generate menu bar icons

func makeMenuBarIcon(pixelSize: Int) -> NSImage {
    let s = CGFloat(pixelSize)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // Template images: black shapes on transparent background.
    // macOS will tint them appropriately for light/dark mode.

    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1.0))

    // Draw two letters side by side: a Cyrillic and Latin letter
    let fontSize = s * 0.52
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
        .foregroundColor: NSColor.black,
    ]

    let text = NSAttributedString(string: "\u{042F}A", attributes: attrs)
    let textSize = text.size()
    let x = (s - textSize.width) / 2.0
    let y = (s - textSize.height) / 2.0
    text.draw(at: NSPoint(x: x, y: y))

    image.unlockFocus()
    return image
}

func generateMenuBarIcons() {
    // 1x: 16x16
    let icon1x = makeMenuBarIcon(pixelSize: 16)
    savePNG(icon1x, to: "\(resourcesDir)/MenuBarIcon.png")
    print("  Created MenuBarIcon.png (16x16)")

    // 2x: 32x32
    let icon2x = makeMenuBarIcon(pixelSize: 32)
    savePNG(icon2x, to: "\(resourcesDir)/MenuBarIcon@2x.png")
    print("  Created MenuBarIcon@2x.png (32x32)")
}

// MARK: - Main

print("Generating app icon set...")
generateIconset()

print("\nGenerating menu bar icons...")
generateMenuBarIcons()

print("\nRunning iconutil to create .icns...")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
let pipe = Pipe()
process.standardError = pipe
try! process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Successfully created \(icnsPath)")
} else {
    let errData = pipe.fileHandleForReading.readDataToEndOfFile()
    let errStr = String(data: errData, encoding: .utf8) ?? "unknown error"
    print("iconutil failed: \(errStr)")
    exit(1)
}

print("\nDone! Generated files:")
print("  \(icnsPath)")
print("  \(resourcesDir)/MenuBarIcon.png")
print("  \(resourcesDir)/MenuBarIcon@2x.png")
