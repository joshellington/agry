// Renders agry's app icon (the eye from EyeGlyph on a dark squircle) into
// Resources/AppIcon.icns. Run from the repo root: swift scripts/icon.swift
import AppKit

/// The eye in EyeGlyph's 20×16 design space (y down), awake mood.
func eyePath() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 1.5, y: 10))
    path.curve(to: NSPoint(x: 18.5, y: 10), quadControl: NSPoint(x: 10, y: 2))
    path.curve(to: NSPoint(x: 1.5, y: 10), quadControl: NSPoint(x: 10, y: 18))
    for (from, to) in [((10.0, 4.4), (10.0, 1.6)), ((5.9, 5.3), (4.7, 2.9)), ((14.1, 5.3), (15.3, 2.9))] {
        path.move(to: NSPoint(x: from.0, y: from.1))
        path.line(to: NSPoint(x: to.0, y: to.1))
    }
    return path
}

extension NSBezierPath {
    func curve(to end: NSPoint, quadControl c: NSPoint) {
        let start = currentPoint
        curve(to: end,
              controlPoint1: NSPoint(x: start.x + 2 / 3 * (c.x - start.x), y: start.y + 2 / 3 * (c.y - start.y)),
              controlPoint2: NSPoint(x: end.x + 2 / 3 * (c.x - end.x), y: end.y + 2 / 3 * (c.y - end.y)))
    }
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let unit = CGFloat(pixels) / 1024

    // macOS icon grid: an 824-point squircle centred on a 1024 canvas.
    let tile = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let squircle = NSBezierPath(roundedRect: tile, xRadius: 185 * unit, yRadius: 185 * unit)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * unit)
    shadow.shadowBlurRadius = 24 * unit
    shadow.set()
    NSColor(white: 0.07, alpha: 1).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(white: 0.16, alpha: 1), ending: NSColor(white: 0.05, alpha: 1))!
        .draw(in: squircle, angle: -90)
    NSColor.white.withAlphaComponent(0.08).setStroke()
    squircle.lineWidth = 2 * unit
    squircle.stroke()

    // The eye, 540 points wide, flipped from the glyph's y-down space.
    let scale = 540 * unit / 20
    let transform = NSAffineTransform()
    transform.translateX(by: 512 * unit - 10 * scale, yBy: 512 * unit + 8.6 * scale)
    transform.scaleX(by: scale, yBy: -scale)
    let eye = eyePath()
    eye.transform(using: transform as AffineTransform)
    eye.lineWidth = 1.35 * scale
    eye.lineCapStyle = .round
    eye.lineJoinStyle = .round
    NSColor(white: 0.94, alpha: 1).setStroke()
    eye.stroke()
    let pupil = NSBezierPath(ovalIn: NSRect(x: 7, y: 7, width: 6, height: 6))
    pupil.transform(using: transform as AffineTransform)
    NSColor(white: 0.94, alpha: 1).setFill()
    pupil.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try render(pixels: 1024).write(to: URL(fileURLWithPath: "build/AppIcon-preview.png"))
print("wrote Resources/AppIcon.icns")
