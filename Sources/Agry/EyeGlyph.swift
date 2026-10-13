import AppKit
import SwiftUI

/// agry's mark: an eye that will not close (agrypnia). Drawn as paths so the
/// same shape serves the menu bar template image and the panel header.
enum EyeGlyph {
    enum Mood: Hashable {
        /// Holding the Mac awake.
        case awake
        /// Holding, and an agent is blocked waiting on the user.
        case attention
        /// Nothing holding; sleep behaves normally.
        case resting
    }

    /// Outline strokes in a 20×16 design space (y down). Lashes point up when
    /// wide awake and down when resting.
    static func outline(_ mood: Mood) -> Path {
        var path = Path()
        switch mood {
        case .awake, .attention:
            path.move(to: CGPoint(x: 1.5, y: 10))
            path.addQuadCurve(to: CGPoint(x: 18.5, y: 10), control: CGPoint(x: 10, y: 2))
            path.addQuadCurve(to: CGPoint(x: 1.5, y: 10), control: CGPoint(x: 10, y: 18))
            for (from, to) in [((10.0, 4.4), (10.0, 1.6)), ((5.9, 5.3), (4.7, 2.9)), ((14.1, 5.3), (15.3, 2.9))] {
                path.move(to: CGPoint(x: from.0, y: from.1))
                path.addLine(to: CGPoint(x: to.0, y: to.1))
            }
        case .resting:
            path.move(to: CGPoint(x: 1.5, y: 7))
            path.addQuadCurve(to: CGPoint(x: 18.5, y: 7), control: CGPoint(x: 10, y: 15))
            for (from, to) in [((10.0, 11.6), (10.0, 14.4)), ((5.9, 10.7), (4.7, 13.1)), ((14.1, 10.7), (15.3, 13.1))] {
                path.move(to: CGPoint(x: from.0, y: from.1))
                path.addLine(to: CGPoint(x: to.0, y: to.1))
            }
        }
        return path
    }

    /// Filled parts, drawn even-odd: a solid pupil, or a ringed one that reads
    /// as "looking at you" when an agent needs attention.
    static func fill(_ mood: Mood) -> Path {
        var path = Path()
        switch mood {
        case .awake:
            path.addEllipse(in: CGRect(x: 7, y: 7, width: 6, height: 6))
        case .attention:
            path.addEllipse(in: CGRect(x: 6.6, y: 6.6, width: 6.8, height: 6.8))
            path.addEllipse(in: CGRect(x: 8.6, y: 8.6, width: 2.8, height: 2.8))
        case .resting:
            break
        }
        return path
    }

    /// A template image for the menu bar (macOS tints it for light/dark).
    static func menuBarImage(_ mood: Mood) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setLineWidth(1.5)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(outline(mood).cgPath)
            context.strokePath()
            context.addPath(fill(mood).cgPath)
            context.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// The glyph as a SwiftUI view, scaled to fit, in the current foreground style.
struct EyeGlyphView: View {
    var mood: EyeGlyph.Mood
    var lineWidth: CGFloat = 1.6

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 20, size.height / 16)
            let offset = CGPoint(x: (size.width - 20 * scale) / 2, y: (size.height - 16 * scale) / 2)
            let transform = CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: scale, y: scale)
            let style = StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round, lineJoin: .round)
            context.stroke(EyeGlyph.outline(mood).applying(transform), with: .foreground, style: style)
            context.fill(EyeGlyph.fill(mood).applying(transform), with: .foreground, style: FillStyle(eoFill: true))
        }
        .aspectRatio(20 / 16, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
