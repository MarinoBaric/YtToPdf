import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Generates the macOS AppIcon set from a square piece of artwork.
//
// The artwork's opaque content is found automatically, scaled into the macOS icon grid
// (an 824 pt body on a 1024 pt canvas), enlarged just enough to fill the continuous-corner
// icon shape, masked to that shape, and given the standard soft drop shadow.
//
// Usage:
//   xcrun swift scripts/make-app-icon.swift <artwork.png|webp> YtToPdf/Assets.xcassets/AppIcon.appiconset
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
      let art = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("unreadable source") }

/// The bounding box of the artwork's opaque pixels, in Core Graphics (y-up) coordinates.
func opaqueBounds(of image: CGImage) -> CGRect {
    let w = image.width, h = image.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: srgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var minX = w, minY = h, maxX = 0, maxY = 0
    for row in 0..<h {
        for x in 0..<w where bytes[(row * w + x) * 4 + 3] > 200 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, row); maxY = max(maxY, row)
        }
    }
    guard maxX >= minX else { return CGRect(x: 0, y: 0, width: w, height: h) }
    // Memory rows run top-down; convert to y-up.
    return CGRect(x: minX, y: h - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let bounds = opaqueBounds(of: art)
let contentCenter = CGPoint(x: bounds.midX, y: bounds.midY)
let contentSide = max(bounds.width, bounds.height)

// macOS icon grid: 1024 canvas, 824 body inset by 100.
let canvas: CGFloat = 1024, body: CGFloat = 824, inset: CGFloat = 100

/// Superellipse (n = 5) – a close match for Apple's continuous-corner icon shape.
func squircle(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n = 5.0, a = rect.width / 2, b = rect.height / 2, cx = rect.midX, cy = rect.midY
    for step in 0...720 {
        let t = Double(step) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func context(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// Draws the artwork scaled so its rounded square spans `body * scale`, centred on the body.
func drawArt(in ctx: CGContext, scale: CGFloat) {
    let factor = body * scale / contentSide
    let width = CGFloat(art.width) * factor, height = CGFloat(art.height) * factor
    let origin = CGPoint(x: canvas / 2 - contentCenter.x * factor, y: canvas / 2 - contentCenter.y * factor)
    ctx.interpolationQuality = .high
    ctx.draw(art, in: CGRect(x: origin.x, y: origin.y, width: width, height: height))
}

let bodyRect = CGRect(x: inset, y: inset, width: body, height: body)
let mask = squircle(in: bodyRect)

/// Fraction of the squircle that the artwork covers with (nearly) opaque pixels.
func coverage(scale: CGFloat) -> Double {
    let ctx = context(Int(canvas))
    drawArt(in: ctx, scale: scale)
    guard let data = ctx.data else { return 0 }
    let bytes = data.bindMemory(to: UInt8.self, capacity: Int(canvas * canvas) * 4)
    var inside = 0, covered = 0
    for y in stride(from: 0, to: Int(canvas), by: 2) {
        for x in stride(from: 0, to: Int(canvas), by: 2) where mask.contains(CGPoint(x: x, y: y)) {
            inside += 1
            // CGContext memory rows run top-down; flip y to match user space.
            let row = Int(canvas) - 1 - y
            if bytes[(row * Int(canvas) + x) * 4 + 3] >= 250 { covered += 1 }
        }
    }
    return Double(covered) / Double(inside)
}

var scale: CGFloat = 1.0
while coverage(scale: scale) < 0.9995 && scale < 1.2 { scale += 0.005 }
print(String(format: "art scale %.3f, coverage %.4f", scale, coverage(scale: scale)))

// Master 1024 icon: soft drop shadow, then the artwork clipped to the squircle.
let master = context(Int(canvas))
master.saveGState()
master.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: CGColor(gray: 0, alpha: 0.32))
master.addPath(mask)
master.setFillColor(CGColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 1))
master.fillPath()
master.restoreGState()
master.saveGState()
master.addPath(mask)
master.clip()
master.clear(bodyRect)
drawArt(in: master, scale: scale)
master.restoreGState()
let masterImage = master.makeImage()!

func write(_ image: CGImage, size: Int, name: String) {
    let ctx = context(size)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    let url = output.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(dest))
}

try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var entries: [[String: String]] = []
for (points, scaleFactor) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scaleFactor
    let name = "icon_\(points)x\(points)\(scaleFactor == 2 ? "@2x" : "").png"
    write(masterImage, size: pixels, name: name)
    entries.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scaleFactor)x", "filename": name])
}
let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))
print("wrote \(entries.count) sizes to \(output.path)")
