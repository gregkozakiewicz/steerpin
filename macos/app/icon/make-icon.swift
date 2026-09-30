// Draws the Steerpin app icon and writes AppIcon.icns next to this file.
// Run: swift macos/app/icon/make-icon.swift
import AppKit

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: size / 1024, y: size / 1024)

    // Tile on the macOS icon grid: 824pt square, 100pt inset.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    tileShadow.shadowOffset = NSSize(width: 0, height: -10)
    tileShadow.shadowBlurRadius = 24
    tileShadow.set()
    NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.23, blue: 0.26, alpha: 1),
               ending: NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.12, alpha: 1))!.draw(in: tile, angle: -90)

    // Pushpin, drawn upright around (0, 0) = needle tip, then tilted.
    ctx.saveGState()
    ctx.translateBy(x: 310, y: 275)
    ctx.rotate(by: -0.62)

    let red = NSColor(calibratedRed: 0.93, green: 0.30, blue: 0.27, alpha: 1)
    let darkRed = NSColor(calibratedRed: 0.70, green: 0.17, blue: 0.16, alpha: 1)

    // Shadow of the pin on the tile.
    NSGraphicsContext.saveGraphicsState()
    let pinShadow = NSShadow()
    pinShadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    pinShadow.shadowOffset = NSSize(width: 18, height: -14)
    pinShadow.shadowBlurRadius = 22
    pinShadow.set()

    // Needle.
    let needle = NSBezierPath()
    needle.move(to: NSPoint(x: 0, y: 0))
    needle.line(to: NSPoint(x: -11, y: 250))
    needle.line(to: NSPoint(x: 11, y: 250))
    needle.close()
    NSColor(calibratedWhite: 0.78, alpha: 1).setFill()
    needle.fill()

    // Base disc.
    let base = NSBezierPath(roundedRect: NSRect(x: -150, y: 240, width: 300, height: 70), xRadius: 35, yRadius: 35)
    darkRed.setFill()
    base.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: red, ending: darkRed)!.draw(in: base, angle: -90)

    // Waist.
    let waist = NSBezierPath()
    waist.move(to: NSPoint(x: -95, y: 300))
    waist.curve(to: NSPoint(x: -62, y: 470), controlPoint1: NSPoint(x: -60, y: 360), controlPoint2: NSPoint(x: -58, y: 420))
    waist.line(to: NSPoint(x: 62, y: 470))
    waist.curve(to: NSPoint(x: 95, y: 300), controlPoint1: NSPoint(x: 58, y: 420), controlPoint2: NSPoint(x: 60, y: 360))
    waist.close()
    NSGradient(colors: [darkRed, red, darkRed])!.draw(in: waist, angle: 0)

    // Top cap.
    let cap = NSBezierPath(roundedRect: NSRect(x: -120, y: 455, width: 240, height: 90), xRadius: 45, yRadius: 45)
    NSGradient(starting: NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.40, alpha: 1), ending: red)!.draw(in: cap, angle: -90)

    // Highlight.
    let shine = NSBezierPath(roundedRect: NSRect(x: -80, y: 505, width: 110, height: 22), xRadius: 11, yRadius: 11)
    NSColor.white.withAlphaComponent(0.35).setFill()
    shine.fill()

    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let iconset = here.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}
try! drawIcon(size: 1024).representation(using: .png, properties: [:])!
    .write(to: here.appendingPathComponent("AppIcon-preview.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", here.appendingPathComponent("AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("Wrote AppIcon.icns")
