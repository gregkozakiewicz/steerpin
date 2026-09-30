// Builds the Steerpin app icon from assets/steerpin-mark.png and writes AppIcon.icns next to this file.
// Run from the repo root: swift macos/app/icon/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let here = root.appendingPathComponent("macos/app/icon")
let mark = NSImage(contentsOf: root.appendingPathComponent("assets/steerpin-mark.png"))!

func bitmap(_ size: Int, _ draw: (CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.imageInterpolation = .high
    draw(CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Draws the mark centred in `rect`, scaled to `height`.
func drawMark(in rect: NSRect, height: CGFloat) {
    let width = height * mark.size.width / mark.size.height
    mark.draw(in: NSRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height))
}

func drawIcon(size: CGFloat) {
    NSGraphicsContext.current!.cgContext.scaleBy(x: size / 1024, y: size / 1024)
    // Tile on the macOS icon grid: 824pt square, 100pt inset.
    let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 22
    shadow.set()
    NSColor.white.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1),
               ending: NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.96, alpha: 1))!.draw(in: tile, angle: -90)
    drawMark(in: tileRect, height: 610)
}

// App icon.
let iconset = here.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! bitmap(base * scale, drawIcon).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}
try! bitmap(1024, drawIcon).representation(using: .png, properties: [:])!
    .write(to: here.appendingPathComponent("AppIcon-preview.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", here.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)

print("Wrote AppIcon.icns")
