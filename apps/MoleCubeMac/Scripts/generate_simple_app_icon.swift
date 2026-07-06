import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Assets.xcassets/SimpleAppIcon.appiconset", isDirectory: true)
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

func line(from start: NSPoint, to end: NSPoint, width: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.move(to: start)
    path.line(to: end)
    path.lineWidth = width
    path.lineCapStyle = .round
    color.setStroke()
    path.stroke()
}

func sparkle(cx: CGFloat, cy: CGFloat, r: CGFloat, fill: NSColor) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: cx, y: cy + r))
    path.line(to: NSPoint(x: cx + r * 0.22, y: cy + r * 0.22))
    path.line(to: NSPoint(x: cx + r, y: cy))
    path.line(to: NSPoint(x: cx + r * 0.22, y: cy - r * 0.22))
    path.line(to: NSPoint(x: cx, y: cy - r))
    path.line(to: NSPoint(x: cx - r * 0.22, y: cy - r * 0.22))
    path.line(to: NSPoint(x: cx - r, y: cy))
    path.line(to: NSPoint(x: cx - r * 0.22, y: cy + r * 0.22))
    path.close()
    fill.setFill()
    path.fill()
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
        throw NSError(domain: "SimpleIcon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    rect(0, 0, size, size).fill()
    NSGraphicsContext.current?.cgContext.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "SimpleIcon", code: 2)
    }
    try data.write(to: folder.appendingPathComponent(name))
}

let image = NSImage(size: canvas)
image.lockFocus()
NSGraphicsContext.current?.shouldAntialias = true

NSColor.clear.setFill()
rect(0, 0, 1024, 1024).fill()

let base = rounded(76, 76, 872, 872, 208)
let baseShadow = NSShadow()
baseShadow.shadowColor = color(0x0b1f1b, 0.18)
baseShadow.shadowBlurRadius = 38
baseShadow.shadowOffset = NSSize(width: 0, height: -16)
baseShadow.set()
NSGradient(colors: [color(0xffffff), color(0xf4fff9), color(0xdff8ed)])?.draw(in: base, angle: -45)
NSShadow().set()

color(0xffffff, 0.85).setStroke()
base.lineWidth = 5
base.stroke()

let badge = oval(218, 218, 588, 588)
let badgeShadow = NSShadow()
badgeShadow.shadowColor = color(0x10241f, 0.30)
badgeShadow.shadowBlurRadius = 28
badgeShadow.shadowOffset = NSSize(width: 0, height: -10)
badgeShadow.set()
NSGradient(colors: [color(0x44504c), color(0x26312e), color(0x151d1b)])?.draw(in: badge, angle: -60)
NSShadow().set()

color(0xffffff, 0.10).setStroke()
badge.lineWidth = 5
badge.stroke()

// A tiny simplified Mole face, kept inside the dark round mark for dock-size clarity.
color(0xffffff).setFill()
oval(386, 514, 74, 88).fill()
oval(564, 514, 74, 88).fill()
color(0x101816).setFill()
oval(413, 545, 28, 34).fill()
oval(591, 545, 28, 34).fill()
color(0xffffff, 0.85).setFill()
oval(422, 565, 9, 10).fill()
oval(600, 565, 9, 10).fill()

NSGradient(colors: [color(0xffb9b0), color(0xf48d88)])?.draw(in: oval(475, 460, 74, 58), angle: -90)
line(from: NSPoint(x: 512, y: 460), to: NSPoint(x: 512, y: 431), width: 5, color: color(0x0e1513, 0.70))
line(from: NSPoint(x: 476, y: 430), to: NSPoint(x: 438, y: 418), width: 4, color: color(0x0e1513, 0.45))
line(from: NSPoint(x: 548, y: 430), to: NSPoint(x: 586, y: 418), width: 4, color: color(0x0e1513, 0.45))

// Minimal cleanup sparkle marks, like the reference screenshot's compact dark icon style.
sparkle(cx: 384, cy: 668, r: 36, fill: color(0xe9fff8))
sparkle(cx: 638, cy: 662, r: 22, fill: color(0x97f0dc))
sparkle(cx: 664, cy: 356, r: 24, fill: color(0xffd56b))

// Small mint orbital accent to connect the simple version back to MoleCube.
let arc = NSBezierPath()
arc.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 228, startAngle: 210, endAngle: 325)
arc.lineWidth = 18
arc.lineCapStyle = .round
color(0x78ebd1, 0.85).setStroke()
arc.stroke()

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

try save(image, size: 1024, name: "MoleCubeIcon-simple.png", in: design)
