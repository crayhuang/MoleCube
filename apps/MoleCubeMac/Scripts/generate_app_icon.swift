import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let design = root.appendingPathComponent("Design", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: design, withIntermediateDirectories: true)

let canvas = NSSize(width: 1024, height: 1024)

func color(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: y, width: w, height: h)
}

func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect(x, y, w, h), xRadius: r, yRadius: r)
}

func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: rect(x, y, w, h))
}

func line(from start: NSPoint, to end: NSPoint, width: CGFloat, color: NSColor, cap: NSBezierPath.LineCapStyle = .round) {
    let path = NSBezierPath()
    path.move(to: start)
    path.line(to: end)
    path.lineWidth = width
    path.lineCapStyle = cap
    color.setStroke()
    path.stroke()
}

func polygon(_ points: [NSPoint]) -> NSBezierPath {
    let path = NSBezierPath()
    guard let first = points.first else { return path }
    path.move(to: first)
    for point in points.dropFirst() {
        path.line(to: point)
    }
    path.close()
    return path
}

func save(_ image: NSImage, size: CGFloat, name: String, in folder: URL = iconset) throws {
    guard
        let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size),
            pixelsHigh: Int(size),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    else {
        throw NSError(domain: "Icon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    NSGraphicsContext.current?.cgContext.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Icon", code: 2)
    }
    try data.write(to: folder.appendingPathComponent(name))
}

let image = NSImage(size: canvas)
image.lockFocus()
NSGraphicsContext.current?.shouldAntialias = true

NSColor.clear.setFill()
rect(0, 0, 1024, 1024).fill()

let base = rounded(68, 68, 888, 888, 220)
let baseShadow = NSShadow()
baseShadow.shadowColor = color(0x155c43, 0.22)
baseShadow.shadowBlurRadius = 44
baseShadow.shadowOffset = NSSize(width: 0, height: -20)
baseShadow.set()
NSGradient(colors: [
    color(0xf6ffe4),
    color(0xbff3b8),
    color(0x53c77e)
])?.draw(in: base, angle: -42)
NSShadow().set()

let topGlow = rounded(104, 526, 816, 344, 168)
NSGradient(colors: [
    color(0xffffff, 0.52),
    color(0xffffff, 0.06)
])?.draw(in: topGlow, angle: -90)

let floorGlow = oval(210, 124, 604, 166)
NSGradient(colors: [
    color(0x158f68, 0.22),
    color(0x158f68, 0)
])?.draw(in: floorGlow, angle: -90)

let cubeShadow = NSShadow()
cubeShadow.shadowColor = color(0x1e7c53, 0.26)
cubeShadow.shadowBlurRadius = 34
cubeShadow.shadowOffset = NSSize(width: 0, height: -15)
cubeShadow.set()

let topFace = polygon([
    NSPoint(x: 512, y: 760),
    NSPoint(x: 742, y: 628),
    NSPoint(x: 512, y: 492),
    NSPoint(x: 282, y: 628)
])
NSGradient(colors: [color(0xfff6aa), color(0xffcb33)])?.draw(in: topFace, angle: -72)

let leftFace = polygon([
    NSPoint(x: 282, y: 628),
    NSPoint(x: 512, y: 492),
    NSPoint(x: 512, y: 240),
    NSPoint(x: 282, y: 374)
])
NSGradient(colors: [color(0x80e6bf), color(0x20b985)])?.draw(in: leftFace, angle: 18)

let rightFace = polygon([
    NSPoint(x: 742, y: 628),
    NSPoint(x: 512, y: 492),
    NSPoint(x: 512, y: 240),
    NSPoint(x: 742, y: 374)
])
NSGradient(colors: [color(0x2fc4a0), color(0x0f9876)])?.draw(in: rightFace, angle: -18)
NSShadow().set()

for face in [topFace, leftFace, rightFace] {
    color(0xffffff, 0.42).setStroke()
    face.lineWidth = 8
    face.stroke()
}

let innerTop = polygon([
    NSPoint(x: 512, y: 636),
    NSPoint(x: 626, y: 570),
    NSPoint(x: 512, y: 504),
    NSPoint(x: 398, y: 570)
])
NSGradient(colors: [color(0xffffff, 0.94), color(0xe8fff1, 0.8)])?.draw(in: innerTop, angle: -90)

let innerLeft = polygon([
    NSPoint(x: 398, y: 570),
    NSPoint(x: 512, y: 504),
    NSPoint(x: 512, y: 382),
    NSPoint(x: 398, y: 448)
])
NSGradient(colors: [color(0xdffff0, 0.94), color(0xb5f1d2, 0.86)])?.draw(in: innerLeft, angle: 12)

let innerRight = polygon([
    NSPoint(x: 626, y: 570),
    NSPoint(x: 512, y: 504),
    NSPoint(x: 512, y: 382),
    NSPoint(x: 626, y: 448)
])
NSGradient(colors: [color(0xb8edd8, 0.9), color(0x8bdcbd, 0.82)])?.draw(in: innerRight, angle: -12)

for face in [innerTop, innerLeft, innerRight] {
    color(0xffffff, 0.62).setStroke()
    face.lineWidth = 5
    face.stroke()
}

let sweep = NSBezierPath()
sweep.move(to: NSPoint(x: 246, y: 296))
sweep.curve(
    to: NSPoint(x: 792, y: 336),
    controlPoint1: NSPoint(x: 382, y: 188),
    controlPoint2: NSPoint(x: 664, y: 196)
)
sweep.lineWidth = 26
sweep.lineCapStyle = .round
color(0xffffff, 0.46).setStroke()
sweep.stroke()

let brushHandle = NSBezierPath()
brushHandle.move(to: NSPoint(x: 624, y: 350))
brushHandle.line(to: NSPoint(x: 780, y: 506))
brushHandle.lineWidth = 38
brushHandle.lineCapStyle = .round
color(0xffffff, 0.78).setStroke()
brushHandle.stroke()
line(from: NSPoint(x: 624, y: 350), to: NSPoint(x: 780, y: 506), width: 17, color: color(0x26b97d))

let bristles = rounded(756, 480, 110, 100, 30)
NSGradient(colors: [color(0xffdf72), color(0xffbf2f)])?.draw(in: bristles, angle: -90)
color(0xffffff, 0.54).setStroke()
bristles.lineWidth = 5
bristles.stroke()

func sparkle(cx: CGFloat, cy: CGFloat, r: CGFloat, fill: NSColor = color(0xffd15b)) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: cx, y: cy + r))
    path.line(to: NSPoint(x: cx + r * 0.24, y: cy + r * 0.24))
    path.line(to: NSPoint(x: cx + r, y: cy))
    path.line(to: NSPoint(x: cx + r * 0.24, y: cy - r * 0.24))
    path.line(to: NSPoint(x: cx, y: cy - r))
    path.line(to: NSPoint(x: cx - r * 0.24, y: cy - r * 0.24))
    path.line(to: NSPoint(x: cx - r, y: cy))
    path.line(to: NSPoint(x: cx - r * 0.24, y: cy + r * 0.24))
    path.close()
    fill.setFill()
    path.fill()
}

sparkle(cx: 238, cy: 722, r: 38)
sparkle(cx: 806, cy: 694, r: 24, fill: color(0xffffff, 0.9))
sparkle(cx: 252, cy: 346, r: 24, fill: color(0xffffff, 0.76))

let shine = NSBezierPath()
shine.move(to: NSPoint(x: 220, y: 806))
shine.curve(
    to: NSPoint(x: 620, y: 886),
    controlPoint1: NSPoint(x: 318, y: 920),
    controlPoint2: NSPoint(x: 500, y: 934)
)
shine.lineWidth = 20
shine.lineCapStyle = .round
color(0xffffff, 0.42).setStroke()
shine.stroke()

color(0x0f6f55, 0.24).setStroke()
base.lineWidth = 5
base.stroke()

image.unlockFocus()

let sizes: [(CGFloat, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (size, name) in sizes {
    try save(image, size: size, name: name)
}

try save(image, size: 1024, name: "MoleCubeIcon-master.png", in: design)
try save(image, size: 1024, name: "MoleCubeIcon-clean.png", in: design)
