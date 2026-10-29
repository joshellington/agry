// Renders agry's app icon (a skull of Rex's mascot, traced from its outline, on
// a dark squircle) into Resources/AppIcon.icns. Run from the repo root:
// swift scripts/icon.swift
import AppKit

extension NSBezierPath {
    func q(_ x: CGFloat, _ y: CGFloat, _ cx: CGFloat, _ cy: CGFloat) {
        let s = currentPoint, e = NSPoint(x: x, y: y), c = NSPoint(x: cx, y: cy)
        curve(to: e,
              controlPoint1: NSPoint(x: s.x + 2 / 3 * (c.x - s.x), y: s.y + 2 / 3 * (c.y - s.y)),
              controlPoint2: NSPoint(x: e.x + 2 / 3 * (c.x - e.x), y: e.y + 2 / 3 * (c.y - e.y)))
    }
    /// Quadratic from the current point to e that passes through p at its middle.
    func through(_ p: NSPoint, to e: NSPoint) {
        let s = currentPoint
        q(e.x, e.y, 2 * p.x - (s.x + e.x) / 2, 2 * p.y - (s.y + e.y) / 2)
    }
    func m(_ x: CGFloat, _ y: CGFloat) { move(to: NSPoint(x: x, y: y)) }
}

func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }

/// A blunt tooth rooted at (x, y), pointing down (dir 1) or up (-1).
func tooth(_ p: NSBezierPath, _ x: CGFloat, _ y: CGFloat, width w: CGFloat, length h: CGFloat, dir: CGFloat) {
    p.m(x - w / 2, y - dir * 12)
    p.q(x + w / 2, y - dir * 12, x, y + dir * (h * 2 - 12))
    p.close()
}

/// A point on the quadratic a → b with control c.
func onQuad(_ a: NSPoint, _ c: NSPoint, _ b: NSPoint, _ t: CGFloat) -> NSPoint {
    let u = 1 - t
    return pt(u * u * a.x + 2 * u * t * c.x + t * t * b.x, u * u * a.y + 2 * u * t * c.y + t * t * b.y)
}

/// A point on the ellipse around the head's centre; degrees counterclockwise from +x.
func around(_ degrees: CGFloat, rx: CGFloat, ry: CGFloat) -> NSPoint {
    let r = degrees * .pi / 180
    return pt(390 + rx * cos(r), 340 - ry * sin(r))
}

/// The mascot's head as a skull, traced from the Rex mascot (y down, ~700 wide).
func skull() -> (bone: [NSBezierPath], holes: NSBezierPath) {
    let spikes = 6, first: CGFloat = 228, step: CGFloat = 23
    let valley = { (k: Int) in around(first - CGFloat(k) * step, rx: 268, ry: 240) }
    let peak = { (k: Int) in around(first - (CGFloat(k) + 0.5) * step, rx: 340, ry: 300) }

    let upperA = pt(345, 556), upperC = pt(470, 540), upperB = pt(628, 466)
    let head = NSBezierPath()
    head.move(to: valley(spikes))
    head.q(575, 112, 480, 70)                   // dome
    head.q(702, 330, 690, 180)                  // brow to snout front
    head.q(upperB.x, upperB.y, 708, 425)        // snout tip
    head.q(upperA.x, upperA.y, upperC.x, upperC.y) // upper jaw
    head.q(valley(0).x, valley(0).y, 240, 610)  // back of skull
    for k in 0..<spikes { head.through(peak(k), to: valley(k + 1)) }
    head.close()

    // Lower jaw, hinged under the cheek, with the mouth open a little.
    let lowerA = pt(312, 600), lowerC = pt(460, 616), lowerB = pt(618, 540)
    let jaw = NSBezierPath()
    jaw.move(to: lowerA)
    jaw.q(lowerB.x, lowerB.y, lowerC.x, lowerC.y)
    jaw.q(565, 662, 648, 612)                   // chin
    jaw.q(lowerA.x, lowerA.y, 330, 705)         // underside
    jaw.close()

    let teeth = NSBezierPath()
    for t in [0.3, 0.46, 0.62, 0.78, 0.92] as [CGFloat] {
        let p = onQuad(upperA, upperC, upperB, t)
        tooth(teeth, p.x, p.y, width: 34, length: 36, dir: 1)
    }
    for t in [0.38, 0.55, 0.72, 0.87] as [CGFloat] {
        let p = onQuad(lowerA, lowerC, lowerB, t)
        tooth(teeth, p.x, p.y, width: 30, length: 30, dir: -1)
    }

    let holes = NSBezierPath()
    holes.appendOval(in: NSRect(x: 222, y: 330, width: 130, height: 160))  // eye socket
    holes.appendOval(in: NSRect(x: 606, y: 282, width: 34, height: 54))    // nostril
    return ([head, jaw, teeth], holes)
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let unit = CGFloat(pixels) / 1024

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

    // Traced space → icon: the skull centred on the canvas at 0.86 scale, y flipped.
    let s: CGFloat = 0.86
    let place = NSAffineTransform()
    place.translateX(by: 512 * unit, yBy: 512 * unit)
    place.scaleX(by: s * unit, yBy: -s * unit)
    place.translateX(by: -378, yBy: -362)
    let (bone, holes) = skull()
    bone.forEach { $0.transform(using: place as AffineTransform) }
    holes.transform(using: place as AffineTransform)

    let cg = NSGraphicsContext.current!.cgContext
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    let shade = NSGradient(starting: NSColor(white: 0.95, alpha: 1), ending: NSColor(white: 0.78, alpha: 1))!
    let bounds = bone.reduce(NSRect.null) { $0.union($1.bounds) }
    for piece in bone {
        NSGraphicsContext.saveGraphicsState()
        piece.addClip()
        shade.draw(in: bounds, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }
    cg.setBlendMode(.clear)
    holes.fill()
    cg.endTransparencyLayer()

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
