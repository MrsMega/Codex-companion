import AppKit

// Rebuild the macOS app icon with: swift make-icon.swift
// The artwork is vector-drawn at 1024 px, then packaged at the standard sizes.
let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let resources = project.appendingPathComponent("Resources", isDirectory: true)
let iconset = project.appendingPathComponent(".build/CodexPromenade.iconset", isDirectory: true)
let canvas = 1024

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255,
            alpha: alpha)
}

func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}

func fill(_ path: NSBezierPath, top: UInt32, bottom: UInt32, outline: UInt32? = nil, width: CGFloat = 0) {
    NSGradient(starting: color(bottom), ending: color(top))!.draw(in: path, angle: 90)
    if let outline {
        color(outline).setStroke()
        path.lineWidth = width
        path.lineJoinStyle = .round
        path.stroke()
    }
}

func stroke(_ points: [NSPoint], color hex: UInt32, width: CGFloat) {
    guard let first = points.first else { return }
    let path = NSBezierPath()
    path.move(to: first)
    for point in points.dropFirst() { path.line(to: point) }
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color(hex).setStroke()
    path.stroke()
}

let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                             bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
NSGraphicsContext.current!.imageInterpolation = .high
NSGraphicsContext.current!.shouldAntialias = true

// Deep blue tile with a light rim and a subtle glow behind the mascot.
let tile = rounded(42, 42, 940, 940, 220)
fill(tile, top: 0x344FA8, bottom: 0x101942, outline: 0x5A78CF, width: 8)
NSGraphicsContext.saveGraphicsState()
tile.addClip()
let glow = NSBezierPath(ovalIn: NSRect(x: 120, y: 265, width: 784, height: 610))
NSGradient(colorsAndLocations: (color(0x779FFF, alpha: 0.34), 0),
           (color(0x668FFF, alpha: 0.0), 1))!.draw(in: glow, relativeCenterPosition: .zero)
NSGraphicsContext.restoreGraphicsState()

// Ground shadow and small feet make the character read well in Finder's small sizes.
color(0x080F32, alpha: 0.32).setFill()
NSBezierPath(ovalIn: NSRect(x: 260, y: 173, width: 506, height: 72)).fill()

for x in [420.0, 543.0] {
    fill(rounded(x, 209, 76, 112, 32), top: 0x638CF9, bottom: 0x3156D7,
         outline: 0x182B70, width: 13)
    fill(rounded(x - 13, 191, 108, 57, 29), top: 0x5F89FA, bottom: 0x365AD8,
         outline: 0x182B70, width: 11)
}

// Arms sit behind the body and cloud-shaped head.
fill(rounded(293, 336, 99, 172, 49), top: 0x86AEFF, bottom: 0x416FEA,
     outline: 0x1A3079, width: 14)
fill(rounded(631, 336, 99, 172, 49), top: 0x86AEFF, bottom: 0x416FEA,
     outline: 0x1A3079, width: 14)
fill(rounded(361, 273, 302, 232, 105), top: 0x7FA7FF, bottom: 0x315BDC,
     outline: 0x172B73, width: 17)
color(0xB9D2FF, alpha: 0.45).setStroke()
let chestShine = NSBezierPath()
chestShine.move(to: NSPoint(x: 424, y: 440))
chestShine.curve(to: NSPoint(x: 600, y: 440), controlPoint1: NSPoint(x: 475, y: 462), controlPoint2: NSPoint(x: 552, y: 462))
chestShine.lineWidth = 8
chestShine.lineCapStyle = .round
chestShine.stroke()
stroke([NSPoint(x: 468, y: 356), NSPoint(x: 487, y: 338), NSPoint(x: 468, y: 320)], color: 0xD5FFFF, width: 11)
stroke([NSPoint(x: 513, y: 321), NSPoint(x: 555, y: 321)], color: 0xD5FFFF, width: 10)

// A single curved outline keeps the cloud head crisp at every icon size.
let head = NSBezierPath()
head.move(to: NSPoint(x: 266, y: 428))
head.curve(to: NSPoint(x: 249, y: 577), controlPoint1: NSPoint(x: 208, y: 463), controlPoint2: NSPoint(x: 202, y: 537))
head.curve(to: NSPoint(x: 313, y: 708), controlPoint1: NSPoint(x: 211, y: 632), controlPoint2: NSPoint(x: 239, y: 689))
head.curve(to: NSPoint(x: 476, y: 774), controlPoint1: NSPoint(x: 335, y: 782), controlPoint2: NSPoint(x: 423, y: 801))
head.curve(to: NSPoint(x: 648, y: 752), controlPoint1: NSPoint(x: 537, y: 822), controlPoint2: NSPoint(x: 615, y: 807))
head.curve(to: NSPoint(x: 784, y: 635), controlPoint1: NSPoint(x: 738, y: 772), controlPoint2: NSPoint(x: 790, y: 706))
head.curve(to: NSPoint(x: 757, y: 454), controlPoint1: NSPoint(x: 829, y: 573), controlPoint2: NSPoint(x: 814, y: 489))
head.curve(to: NSPoint(x: 588, y: 387), controlPoint1: NSPoint(x: 737, y: 398), controlPoint2: NSPoint(x: 652, y: 369))
head.curve(to: NSPoint(x: 381, y: 394), controlPoint1: NSPoint(x: 531, y: 366), controlPoint2: NSPoint(x: 434, y: 367))
head.curve(to: NSPoint(x: 266, y: 428), controlPoint1: NSPoint(x: 334, y: 374), controlPoint2: NSPoint(x: 288, y: 390))
head.close()
fill(head, top: 0x91B9FF, bottom: 0x426CED, outline: 0x182B75, width: 19)

// Terminal face: the cyan prompt echoes the mascot's on-screen expression.
let face = rounded(316, 457, 392, 240, 78)
fill(face, top: 0x26366C, bottom: 0x14204B, outline: 0x101A44, width: 16)
color(0x7196EA, alpha: 0.38).setStroke()
let faceRim = rounded(333, 474, 358, 206, 66)
faceRim.lineWidth = 5
faceRim.stroke()
stroke([NSPoint(x: 395, y: 609), NSPoint(x: 443, y: 574), NSPoint(x: 395, y: 539)], color: 0xA5F6FF, width: 25)
stroke([NSPoint(x: 508, y: 536), NSPoint(x: 587, y: 536)], color: 0xA5F6FF, width: 24)

NSGraphicsContext.restoreGraphicsState()

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let png = image.representation(using: .png, properties: [:])!
let master = resources.appendingPathComponent("CodexPromenade-icon.png")
try png.write(to: master)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in variants {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                  bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current!.imageInterpolation = .high
    NSGraphicsContext.current!.shouldAntialias = true
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!
        .write(to: iconset.appendingPathComponent(name))
}
let icon = resources.appendingPathComponent("CodexPromenade.icns")
func bigEndian(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.bigEndian) { Data($0) }
}
let chunks: [(String, String)] = [
    ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]
var payload = Data()
for (type, name) in chunks {
    let bytes = try Data(contentsOf: iconset.appendingPathComponent(name))
    payload.append(type.data(using: .ascii)!)
    payload.append(bigEndian(UInt32(bytes.count + 8)))
    payload.append(bytes)
}
var archive = Data("icns".utf8)
archive.append(bigEndian(UInt32(payload.count + 8)))
archive.append(payload)
try archive.write(to: icon)
print("Icône créée : \(icon.path)")
