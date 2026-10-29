import AppKit
import SwiftUI

/// agry's mark: a skull of Rex's mascot, traced from its outline. Drawn as
/// paths so the same shape serves the menu bar image and the panel. The app
/// icon (scripts/icon.swift) draws the same skull with teeth.
enum SkullGlyph {
    enum Mood: Hashable {
        /// Holding the Mac awake.
        case awake
        /// Holding, and an agent is blocked waiting on the user.
        case attention
        /// Nothing holding; sleep behaves normally.
        case resting
    }

    /// Sodium-lamp amber: the eye socket's color when an agent needs the user,
    /// and the panel's "needs you" color (Theme.amber).
    static let attentionColor = NSColor(red: 1.0, green: 0.69, blue: 0.13, alpha: 1)

    /// The traced design space (y down) that the glyph is fitted from.
    static let bounds = CGRect(x: 40, y: 38, width: 680, height: 672)

    /// Head and lower jaw.
    static let bone: Path = {
        // Points on an ellipse around the head's centre; degrees counterclockwise from +x.
        func around(_ degrees: CGFloat, rx: CGFloat, ry: CGFloat) -> CGPoint {
            let r = degrees * .pi / 180
            return CGPoint(x: 390 + rx * cos(r), y: 340 - ry * sin(r))
        }
        let spikes = 6
        let valley = { (k: Int) in around(228 - CGFloat(k) * 23, rx: 268, ry: 240) }
        let peak = { (k: Int) in around(228 - (CGFloat(k) + 0.5) * 23, rx: 340, ry: 300) }

        var path = Path()
        path.move(to: valley(spikes))
        path.addQuadCurve(to: CGPoint(x: 575, y: 112), control: CGPoint(x: 480, y: 70))   // dome
        path.addQuadCurve(to: CGPoint(x: 702, y: 330), control: CGPoint(x: 690, y: 180))  // brow
        path.addQuadCurve(to: CGPoint(x: 628, y: 466), control: CGPoint(x: 708, y: 425))  // snout
        path.addQuadCurve(to: CGPoint(x: 345, y: 556), control: CGPoint(x: 470, y: 540))  // upper jaw
        path.addQuadCurve(to: valley(0), control: CGPoint(x: 240, y: 610))                // back of skull
        // Spikes down the back of the head, each a curve through its peak.
        for k in 0..<spikes {
            let start = valley(k), end = valley(k + 1), tip = peak(k)
            path.addQuadCurve(to: end, control: CGPoint(x: 2 * tip.x - (start.x + end.x) / 2,
                                                         y: 2 * tip.y - (start.y + end.y) / 2))
        }
        path.closeSubpath()

        path.move(to: CGPoint(x: 312, y: 600))
        path.addQuadCurve(to: CGPoint(x: 618, y: 540), control: CGPoint(x: 460, y: 616))  // lower lip
        path.addQuadCurve(to: CGPoint(x: 565, y: 662), control: CGPoint(x: 648, y: 612))  // chin
        path.addQuadCurve(to: CGPoint(x: 312, y: 600), control: CGPoint(x: 330, y: 705))  // underside
        path.closeSubpath()
        return path
    }()

    static let socket = Path(ellipseIn: CGRect(x: 222, y: 330, width: 130, height: 160))
    static let nostril = Path(ellipseIn: CGRect(x: 606, y: 282, width: 34, height: 54))

    /// The closed eye drawn when resting.
    static let lid: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 232, y: 410))
        path.addQuadCurve(to: CGPoint(x: 342, y: 410), control: CGPoint(x: 287, y: 455))
        return path
    }()

    /// Solid bone with the socket and nostril cut out; fill with even-odd.
    static let solid: Path = {
        var path = bone
        path.addPath(socket)
        path.addPath(nostril)
        return path
    }()

    /// Fits the design space centred in a frame of the given size.
    static func fit(_ size: CGSize) -> CGAffineTransform {
        let scale = min(size.width / bounds.width, size.height / bounds.height)
        return CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
    }

    /// The menu bar image. Awake and resting are templates (macOS tints them);
    /// attention is drawn in color so the socket can be amber, with the bone
    /// in the label color so it still follows the menu bar's appearance.
    /// Resting is an outline with the eye closed.
    static func menuBarImage(_ mood: Mood) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let transform = fit(size)
            let ink = mood == .attention ? NSColor.labelColor.cgColor : NSColor.black.cgColor
            switch mood {
            case .awake, .attention:
                context.setFillColor(ink)
                context.addPath(solid.applying(transform).cgPath)
                context.fillPath(using: .evenOdd)
                if mood == .attention {
                    context.setFillColor(attentionColor.cgColor)
                    context.addPath(socket.applying(transform).cgPath)
                    context.fillPath()
                }
            case .resting:
                context.setStrokeColor(ink)
                context.setLineWidth(1.2)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.addPath(bone.applying(transform).cgPath)
                context.addPath(lid.applying(transform).cgPath)
                context.strokePath()
            }
            return true
        }
        image.isTemplate = mood != .attention
        return image
    }
}

/// The glyph as a SwiftUI view, scaled to fit. The bone uses the current
/// foreground style; the socket turns amber for attention. `lineWidth` is the
/// resting outline's width.
struct SkullGlyphView: View {
    var mood: SkullGlyph.Mood
    var lineWidth: CGFloat = 1.6

    var body: some View {
        Canvas { context, size in
            let transform = SkullGlyph.fit(size)
            switch mood {
            case .awake, .attention:
                context.fill(SkullGlyph.solid.applying(transform), with: .foreground, style: FillStyle(eoFill: true))
                if mood == .attention {
                    context.fill(SkullGlyph.socket.applying(transform),
                                 with: .color(Color(nsColor: SkullGlyph.attentionColor)))
                }
            case .resting:
                let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                context.stroke(SkullGlyph.bone.applying(transform), with: .foreground, style: style)
                context.stroke(SkullGlyph.lid.applying(transform), with: .foreground, style: style)
            }
        }
        .aspectRatio(SkullGlyph.bounds.width / SkullGlyph.bounds.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
