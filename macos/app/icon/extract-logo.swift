// Pulls the blue artwork out of assets/logo.png onto a transparent background.
// Writes assets/steerpin-logo.png (pin + wordmark), assets/steerpin-logo-dark.png (light blue,
// for dark backgrounds) and assets/steerpin-mark.png (pin only).
// Run: swift macos/app/icon/extract-logo.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath) // run from the repo root
let source = NSImage(contentsOf: root.appendingPathComponent("assets/logo.png"))!
let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let w = cg.width, h = cg.height
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

typealias RGB = (r: Double, g: Double, b: Double)
// Brand blue, sampled from the logo, and a light blue that reads on dark backgrounds.
let brand: RGB = (0.169, 0.337, 0.525)
let brandOnDark: RGB = (0.64, 0.77, 0.94)

// Coverage = how far a pixel is from paper-white towards the brand blue (keeps anti-aliasing).
var coverage = [Double](repeating: 0, count: w * h)
var sum = (r: 0.0, g: 0.0, b: 0.0, n: 0.0)
for i in 0..<(w * h) {
    let a = Double(pixels[i * 4 + 3]) / 255
    guard a > 0 else { continue }
    let r = Double(pixels[i * 4]) / 255 / a, g = Double(pixels[i * 4 + 1]) / 255 / a, b = Double(pixels[i * 4 + 2]) / 255 / a
    let lum = 0.299 * r + 0.587 * g + 0.114 * b
    let blueness = b - r
    guard blueness > 0.12 else { continue }
    let c = min(1, max(0, (0.88 - lum) / (0.88 - 0.34))) * a
    coverage[i] = c
    if c > 0.95 { sum.r += r; sum.g += g; sum.b += b; sum.n += 1 }
}
print(String(format: "sampled blue: #%02X%02X%02X", Int(sum.r / sum.n * 255), Int(sum.g / sum.n * 255), Int(sum.b / sum.n * 255)))

// Bounding box of covered pixels in a row range (row 0 = top of the image).
func bounds(rows: Range<Int>) -> (x: Int, y: Int, w: Int, h: Int) {
    var minX = w, maxX = 0, minY = h, maxY = 0
    for y in rows { for x in 0..<w where coverage[y * w + x] > 0.3 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    return (minX, minY, maxX - minX + 1, maxY - minY + 1)
}

func write(_ box: (x: Int, y: Int, w: Int, h: Int), pad: Int, color: RGB = brand, to name: String) {
    let ow = box.w + pad * 2, oh = box.h + pad * 2
    var out = [UInt8](repeating: 0, count: ow * oh * 4)
    for y in 0..<box.h { for x in 0..<box.w {
        let c = coverage[(box.y + y) * w + (box.x + x)]
        guard c > 0.02 else { continue }
        let o = ((y + pad) * ow + (x + pad)) * 4
        out[o] = UInt8(color.r * c * 255); out[o + 1] = UInt8(color.g * c * 255)
        out[o + 2] = UInt8(color.b * c * 255); out[o + 3] = UInt8(c * 255)
    } }
    let octx = CGContext(data: &out, width: ow, height: oh, bitsPerComponent: 8, bytesPerRow: ow * 4,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let rep = NSBitmapImageRep(cgImage: octx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("assets/\(name)"))
    print("wrote assets/\(name) \(ow)x\(oh)")
}

// The pin ends at ~74% of the height; the wordmark starts at ~81%.
write(bounds(rows: 0..<h), pad: 24, to: "steerpin-logo.png")
write(bounds(rows: 0..<h), pad: 24, color: brandOnDark, to: "steerpin-logo-dark.png")
write(bounds(rows: 0..<Int(Double(h) * 0.78)), pad: 24, to: "steerpin-mark.png")
