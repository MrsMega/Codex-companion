import AppKit
import ImageIO

struct Sprite: Decodable {
    let file: String
    let frames: Int
    let pose: String
}

struct Manifest: Decodable { let sprites: [Sprite] }

struct Mean {
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

    func distance(from other: Mean) -> Double {
        guard count > 100, other.count > 100 else { return .infinity }
        return max(abs(r / count - other.r / other.count),
                   abs(g / count - other.g / other.count),
                   abs(b / count - other.b / other.count))
    }
}

struct Measurements {
    var blue = Mean()
    var upper = Mean()
    var lower = Mean()
    var navy = Mean()
    var minX = 192
    var maxX = -1
    var minY = 208
    var maxY = -1

    var width: Int { maxX - minX + 1 }
}

func image(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func measure(_ image: CGImage) -> Measurements {
    precondition(image.width == 192 && image.height == 208)
    var data = [UInt8](repeating: 0, count: 192 * 208 * 4)
    data.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: 192, height: 208,
                                bitsPerComponent: 8, bytesPerRow: 192 * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: 192, height: 208))
    }
    var result = Measurements()
    for y in 0..<208 {
        for x in 0..<192 {
            let i = (y * 192 + x) * 4
            let r = data[i], g = data[i + 1], b = data[i + 2], a = data[i + 3]
            if a > 128 {
                result.minX = min(result.minX, x)
                result.maxX = max(result.maxX, x)
                result.minY = min(result.minY, y)
                result.maxY = max(result.maxY, y)
            }
            guard a > 220 else { continue }
            if Int(b) > 170 && Int(b) > Int(g) + 35 &&
               Int(g) > Int(r) + 25 && r > 30 {
                result.blue.add(r, g, b)
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

let resources = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let project = resources.deletingLastPathComponent()
let manifestURL = project.appendingPathComponent("sprite-manifest.json")
let manifest = try JSONDecoder().decode(Manifest.self,
                                        from: Data(contentsOf: manifestURL))
var errors = [String]()
let names = manifest.sprites.map(\.file)
if Set(names).count != names.count { errors.append("Entrées répétées dans sprite-manifest.json") }
let onDisk = Set(try FileManager.default.contentsOfDirectory(atPath: resources.path)
    .filter { $0.hasPrefix("codex-") && $0.hasSuffix(".png") })
for name in onDisk.subtracting(Set(names)).sorted() {
    errors.append("\(name) : absent de sprite-manifest.json")
}
for name in Set(names).subtracting(onDisk).sorted() {
    errors.append("\(name) : image manquante")
}

let atlasURL = resources.appendingPathComponent("codex-spritesheet-v6.webp")
guard let atlas = image(atlasURL), atlas.width == 1536, atlas.height == 2288,
      let idle = atlas.cropping(to: CGRect(x: 0, y: 0, width: 192, height: 208)) else {
    fputs("Planche d'origine manquante ou invalide\n", stderr)
    exit(1)
}
let reference = measure(idle)
var checkedFrames = 0
for sprite in manifest.sprites {
    if !onDisk.contains(sprite.file) { continue }
    guard ["standing", "seated", "carried", "rotating"].contains(sprite.pose) else {
        errors.append("\(sprite.file) : type de pose inconnu")
        continue
    }
    guard sprite.frames > 0, sprite.frames <= 16,
          let strip = image(resources.appendingPathComponent(sprite.file)) else {
        errors.append("\(sprite.file) : image illisible ou nombre d'images invalide")
        continue
    }
    guard strip.width == 192 * sprite.frames && strip.height == 208 else {
        errors.append("\(sprite.file) : attendu \(192 * sprite.frames) × 208 px, obtenu \(strip.width) × \(strip.height) px")
        continue
    }
    for frame in 0..<sprite.frames {
        let crop = strip.cropping(to: CGRect(x: frame * 192, y: 0,
                                             width: 192, height: 208))!
        let m = measure(crop)
        let id = "\(sprite.file) image \(frame + 1)"
        checkedFrames += 1
        if m.minX < 2 || m.maxX > 189 || m.minY < 1 || m.maxY > 205 {
            errors.append("\(id) : dessin coupé ou hors de la case")
        }
        if m.blue.distance(from: reference.blue) > 11 {
            errors.append("\(id) : bleu éloigné de la référence")
        }
        if sprite.pose != "rotating" &&
           (m.upper.distance(from: reference.upper) > 13 ||
            m.lower.distance(from: reference.lower) > 13) {
            errors.append("\(id) : dégradé tête/corps incohérent")
        }
        if m.navy.distance(from: reference.navy) > 16 {
            errors.append("\(id) : contour ou écran bleu marine incohérent")
        }
        switch sprite.pose {
        case "standing":
            if !(136...158).contains(m.width) || !(197...201).contains(m.maxY) {
                errors.append("\(id) : taille ou ligne de sol incohérente")
            }
        case "seated":
            if !(138...150).contains(m.width) || !(196...202).contains(m.maxY) {
                errors.append("\(id) : taille assise ou ligne de sol incohérente")
            }
        case "carried":
            if !(140...155).contains(m.width) {
                errors.append("\(id) : taille de la pose portée incohérente")
            }
        default: break
        }
    }
}

if errors.isEmpty {
    print("Sprites valides : \(manifest.sprites.count) planches, \(checkedFrames) images")
} else {
    for error in errors { fputs("• \(error)\n", stderr) }
    exit(1)
}
