import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Assets.xcassets/LineAppIcon.appiconset", isDirectory: true)
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

func line(_ points: [NSPoint], width: CGFloat, stroke: NSColor) {
    guard let first = points.first else { return }
    let path = NSBezierPath()
    path.move(to: first)
    for point in points.dropFirst() {
        path.line(to: point)
    }
    path.lineWidth = width
    path.lineJoinStyle = .round
    path.lineCapStyle = .round
    stroke.setStroke()
    path.stroke()
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
        throw NSError(domain: "LineIcon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    rect(0, 0, size, size).fill()
    NSGraphicsContext.current?.cgContext.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "LineIcon", code: 2)
    }
    try data.write(to: folder.appendingPathComponent(name))
}

let image = NSImage(size: canvas)
image.lockFocus()
NSGraphicsContext.current?.shouldAntialias = true

NSColor.clear.setFill()
rect(0, 0, 1024, 1024).fill()

let base = rounded(88, 88, 848, 848, 198)
let shadow = NSShadow()
shadow.shadowColor = color(0x05201b, 0.16)
shadow.shadowBlurRadius = 34
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
NSGradient(colors: [color(0xffffff), color(0xf5fff9), color(0xe6f9ee)])?.draw(in: base, angle: -42)
NSShadow().set()

color(0xffffff, 0.95).setStroke()
base.lineWidth = 4
base.stroke()

let markShadow = NSShadow()
markShadow.shadowColor = color(0x10241f, 0.12)
markShadow.shadowBlurRadius = 18
markShadow.shadowOffset = NSSize(width: 0, height: -8)
markShadow.set()

let outer = NSBezierPath()
outer.move(to: NSPoint(x: 512, y: 238))
outer.line(to: NSPoint(x: 750, y: 376))
outer.line(to: NSPoint(x: 750, y: 648))
outer.line(to: NSPoint(x: 512, y: 786))
outer.line(to: NSPoint(x: 274, y: 648))
outer.line(to: NSPoint(x: 274, y: 376))
outer.close()
outer.lineWidth = 34
outer.lineJoinStyle = .round
outer.lineCapStyle = .round
color(0x26332f).setStroke()
outer.stroke()
NSShadow().set()

line([
    NSPoint(x: 512, y: 238),
    NSPoint(x: 512, y: 502),
    NSPoint(x: 750, y: 648)
], width: 30, stroke: color(0x26332f))

line([
    NSPoint(x: 274, y: 648),
    NSPoint(x: 512, y: 502),
    NSPoint(x: 750, y: 376)
], width: 30, stroke: color(0x26332f))

// Minimal Mole hint: two tunnel arcs and a small nose/dot, kept abstract.
let leftArc = NSBezierPath()
leftArc.appendArc(withCenter: NSPoint(x: 430, y: 520), radius: 94, startAngle: 118, endAngle: 260)
leftArc.lineWidth = 30
leftArc.lineCapStyle = .round
color(0x26c9a8).setStroke()
leftArc.stroke()

let rightArc = NSBezierPath()
rightArc.appendArc(withCenter: NSPoint(x: 594, y: 520), radius: 94, startAngle: -80, endAngle: 62)
rightArc.lineWidth = 30
rightArc.lineCapStyle = .round
color(0x26c9a8).setStroke()
rightArc.stroke()

NSGradient(colors: [color(0x27dcb8), color(0x16a88e)])?.draw(in: NSBezierPath(ovalIn: rect(472, 482, 80, 80)), angle: -90)

let sparkle = NSBezierPath()
sparkle.move(to: NSPoint(x: 720, y: 714))
sparkle.line(to: NSPoint(x: 736, y: 676))
sparkle.line(to: NSPoint(x: 774, y: 660))
sparkle.line(to: NSPoint(x: 736, y: 644))
sparkle.line(to: NSPoint(x: 720, y: 606))
sparkle.line(to: NSPoint(x: 704, y: 644))
sparkle.line(to: NSPoint(x: 666, y: 660))
sparkle.line(to: NSPoint(x: 704, y: 676))
sparkle.close()
color(0x26332f).setFill()
sparkle.fill()

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

try save(image, size: 1024, name: "MoleCubeIcon-line.png", in: design)
