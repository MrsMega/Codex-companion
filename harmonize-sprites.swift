import AppKit
import ImageIO

// Match supplementary animation strips to the official idle sprite. Keep the
// original frame layout and alpha; only blue surfaces and their navy shading
// are corrected. Seated poses are also brought to the same head scale.
struct Color {
    var r = 0.0
    var g = 0.0
    var b = 0.0
    var count = 0.0

    mutating func add(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r += Double(r)
        self.g += Double(g)
        self.b += Double(b)
        count += 1
    }

    var mean: (Double, Double, Double) {
        precondition(count > 100)
        return (r / count, g / count, b / count)
    }
}

struct Palette {
    var upper = Color()
    var lower = Color()
    var navy = Color()
}

struct Sprite: Decodable {
    let file: String
    let frames: Int
    let pose: String
}

struct Manifest: Decodable { let sprites: [Sprite] }

func load(_ url: URL) -> CGImage {
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(source, 0, nil)!
}

func pixels(_ image: CGImage) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    data.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: image.width,
                                height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0,
                                       width: image.width, height: image.height))
    }
    return data
}

func palette(_ data: [UInt8], width: Int, height: Int) -> Palette {
    var result = Palette()
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            let r = data[i], g = data[i + 1], b = data[i + 2], a = data[i + 3]
            guard a > 220 else { continue }
            if Int(b) > 170 && Int(b) > Int(g) + 35 &&
               Int(g) > Int(r) + 25 && r > 30 {
                if y < 125 { result.upper.add(r, g, b) }
                if y >= 135 { result.lower.add(r, g, b) }
            } else if b > 55 && b < 180 && r < 80 && g < 115 &&
                      Int(b) > Int(g) + 25 {
                result.navy.add(r, g, b)
            }
        }
    }
    return result
}

func difference(_ target: Color, _ source: Color) -> [Double] {
    let t = target.mean, s = source.mean
    return [t.0 - s.0, t.1 - s.1, t.2 - s.2]
}

func makeImage(_ data: inout [UInt8], width: Int, height: Int) -> CGImage {
    data.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: width,
                                height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }
}

func save(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                      "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
}

let sourceDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let projectDirectory = sourceDirectory.deletingLastPathComponent()
let manifestURL = projectDirectory.appendingPathComponent("sprite-manifest.json")
let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
let requested = Set(CommandLine.arguments.dropFirst(3))
let available = Set(manifest.sprites.map(\.file))
precondition(requested.isSubset(of: available), "Unknown sprite; add it to sprite-manifest.json")
let strips = manifest.sprites.filter { requested.isEmpty || requested.contains($0.file) }
try FileManager.default.createDirectory(at: outputDirectory,
                                        withIntermediateDirectories: true)
let atlas = load(sourceDirectory.appendingPathComponent("codex-spritesheet-v6.webp"))
let idle = atlas.cropping(to: CGRect(x: 0, y: 0, width: 192, height: 208))!
let reference = palette(pixels(idle), width: 192, height: 208)

for strip in strips {
    let image = load(sourceDirectory.appendingPathComponent(strip.file))
    precondition(image.height == 208 && image.width == strip.frames * 192)
    var data = pixels(image)
    let current = palette(data, width: image.width, height: 208)
    let upper = difference(reference.upper, current.upper)
    let lower = difference(reference.lower, current.lower)
    let navy = difference(reference.navy, current.navy)
    let referenceOverall = Color(r: reference.upper.r + reference.lower.r,
                                 g: reference.upper.g + reference.lower.g,
                                 b: reference.upper.b + reference.lower.b,
                                 count: reference.upper.count + reference.lower.count)
    let currentOverall = Color(r: current.upper.r + current.lower.r,
                               g: current.upper.g + current.lower.g,
                               b: current.upper.b + current.lower.b,
                               count: current.upper.count + current.lower.count)
    let overall = difference(referenceOverall, currentOverall)

    for y in 0..<208 {
        let blend = min(1.0, max(0.0, (Double(y) - 125.0) / 10.0))
        for x in 0..<image.width {
            let i = (y * image.width + x) * 4
            let alpha = Double(data[i + 3])
            guard alpha > 0 else { continue }
            let r = Double(data[i]) * 255 / alpha
            let g = Double(data[i + 1]) * 255 / alpha
            let b = Double(data[i + 2]) * 255 / alpha
            let navyPixel = b > 55 && b < 180 && r < 80 && g < 115 && b > g + 25
            let bluePixel = b > 90 && b > g + 18 && g > r + 7 && r > 20
            guard navyPixel || bluePixel else { continue }
            let weight = navyPixel ? 1.0 : min(1.0, max(0.0, (b - 90) / 80))
            for channel in 0..<3 {
                let fillShift = strip.pose == "rotating" ? overall[channel] :
                    upper[channel] * (1 - blend) + lower[channel] * blend
                let shift = navyPixel ? navy[channel] : fillShift * weight
                let value = Double(data[i + channel]) + shift * alpha / 255
                data[i + channel] = UInt8(max(0, min(255, value.rounded())))
            }
        }
    }

    var corrected = makeImage(&data, width: image.width, height: image.height)
    if strip.pose == "seated" {
        let output = NSBitmapImageRep(bitmapDataPlanes: nil,
                                      pixelsWide: image.width, pixelsHigh: 208,
                                      bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: output)
        NSGraphicsContext.current?.imageInterpolation = .high
        for frame in 0..<(image.width / 192) {
            let crop = corrected.cropping(to: CGRect(x: frame * 192, y: 0,
                                                      width: 192, height: 208))!
            var minX = 192, maxX = -1, maxY = -1
            for y in 0..<208 {
                for x in 0..<192 {
                    if data[(y * image.width + frame * 192 + x) * 4 + 3] > 128 {
                        minX = min(minX, x)
                        maxX = max(maxX, x)
                        maxY = max(maxY, y)
                    }
                }
            }
            let center = CGFloat(minX + maxX) / 2
            let sole = CGFloat(207 - maxY)
            let scale = min(CGFloat(1.10), CGFloat(144) / CGFloat(maxX - minX + 1))
            let destination = NSRect(x: CGFloat(frame * 192 + 96) - center * scale,
                                     y: 8 - sole * scale,
                                     width: 192 * scale, height: 208 * scale)
            NSImage(cgImage: crop, size: NSSize(width: 192, height: 208)).draw(
                in: destination, from: .zero, operation: .sourceOver, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
        corrected = output.cgImage!
    }
    save(corrected, to: outputDirectory.appendingPathComponent(strip.file))
    print(strip.file)
}
