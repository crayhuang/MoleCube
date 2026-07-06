import AppKit
import CoreImage

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Assets.xcassets/SmoothAppIcon.appiconset", isDirectory: true)
let design = root.appendingPathComponent("Design", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: design, withIntermediateDirectories: true)

let inputPath = CommandLine.arguments.dropFirst().first ?? design.appendingPathComponent("MoleCubeIcon-master.png").path
let inputURL = URL(fileURLWithPath: inputPath)

func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: y, width: w, height: h)
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
        throw NSError(domain: "SmoothIcon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    rect(0, 0, size, size).fill()
    NSGraphicsContext.current?.cgContext.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "SmoothIcon", code: 2)
    }
    try data.write(to: folder.appendingPathComponent(name))
}

func centeredSquare(from size: NSSize) -> NSRect {
    let side = min(size.width, size.height)
    return NSRect(
        x: (size.width - side) / 2,
        y: (size.height - side) / 2,
        width: side,
        height: side
    )
}

guard let sourceImage = NSImage(contentsOf: inputURL) else {
    throw NSError(domain: "SmoothIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not load \(inputPath)"])
}

let canvas = NSSize(width: 1024, height: 1024)
let base = NSImage(size: canvas)
base.lockFocus()
NSGraphicsContext.current?.shouldAntialias = true
NSGraphicsContext.current?.imageInterpolation = .high
NSColor.clear.setFill()
rect(0, 0, 1024, 1024).fill()
sourceImage.draw(
    in: rect(0, 0, 1024, 1024),
    from: centeredSquare(from: sourceImage.size),
    operation: .sourceOver,
    fraction: 1,
    respectFlipped: false,
    hints: [.interpolation: NSImageInterpolation.high]
)
base.unlockFocus()

let context = CIContext(options: [.useSoftwareRenderer: false])
let inputCG = base.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let ciInput = CIImage(cgImage: inputCG)

let noiseReduced = ciInput
    .applyingFilter("CINoiseReduction", parameters: [
        "inputNoiseLevel": 0.018,
        "inputSharpness": 0.42
    ])

let soft = noiseReduced
    .clampedToExtent()
    .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 0.55])
    .cropped(to: ciInput.extent)

let softened = NSImage(size: canvas)
softened.lockFocus()
NSGraphicsContext.current?.shouldAntialias = true
NSGraphicsContext.current?.imageInterpolation = .high
NSColor.clear.setFill()
rect(0, 0, 1024, 1024).fill()

if let baseCG = context.createCGImage(noiseReduced, from: ciInput.extent),
   let softCG = context.createCGImage(soft, from: ciInput.extent) {
    NSGraphicsContext.current?.cgContext.draw(baseCG, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    NSGraphicsContext.current?.cgContext.setAlpha(0.28)
    NSGraphicsContext.current?.cgContext.draw(softCG, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
}
softened.unlockFocus()

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
    try save(softened, size: size, name: name)
}

try save(softened, size: 1024, name: "MoleCubeIcon-smooth.png", in: design)
