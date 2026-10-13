import AppKit
import SwiftUI

/// agry's mark: an eye that will not close (agrypnia). Drawn as paths so the
/// same shape serves the menu bar image and the panel header.
enum EyeGlyph {
    enum Mood: Hashable {
        /// Holding the Mac awake.
        case awake
        /// Holding, and an agent is blocked waiting on the user.
        case attention
        /// Nothing holding; sleep behaves normally.
        case resting
    }

    /// Sodium-lamp amber: the pupil's color when an agent needs the user, and
    /// the panel's "needs you" color (Theme.amber).
    static let attentionColor = NSColor(red: 1.0, green: 0.69, blue: 0.13, alpha: 1)

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

    /// The pupil, absent when resting.
    static func pupil(_ mood: Mood) -> Path {
        mood == .resting ? Path() : Path(ellipseIn: CGRect(x: 7, y: 7, width: 6, height: 6))
    }

    /// The menu bar image. Awake and resting are templates (macOS tints them);
    /// attention is drawn in color so the pupil can be orange, with the outline
    /// in the label color so it still follows the menu bar's appearance.
    static func menuBarImage(_ mood: Mood) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let ink = mood == .attention ? NSColor.labelColor.cgColor : NSColor.black.cgColor
            context.setLineWidth(1.5)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setStrokeColor(ink)
            context.addPath(outline(mood).cgPath)
            context.strokePath()
            context.setFillColor(mood == .attention ? attentionColor.cgColor : ink)
            context.addPath(pupil(mood).cgPath)
            context.fillPath()
            return true
        }
        image.isTemplate = mood != .attention
        return image
    }
}

/// The glyph as a SwiftUI view, scaled to fit. The outline uses the current
/// foreground style; the pupil turns orange for attention.
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
            let pupil = EyeGlyph.pupil(mood).applying(transform)
            context.fill(pupil, with: mood == .attention ? .color(Color(nsColor: EyeGlyph.attentionColor)) : .foreground)
        }
        .aspectRatio(20 / 16, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
