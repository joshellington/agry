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
            // When watching, the right lash makes room for the badge it glances at.
            var lashes = [((10.0, 4.4), (10.0, 1.6)), ((5.9, 5.3), (4.7, 2.9))]
            if mood == .awake { lashes.append(((14.1, 5.3), (15.3, 2.9))) }
            for (from, to) in lashes {
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

    /// The pupil. When watching, it shifts up and right toward the badge.
    static func fill(_ mood: Mood) -> Path {
        var path = Path()
        switch mood {
        case .awake:
            path.addEllipse(in: CGRect(x: 7, y: 7, width: 6, height: 6))
        case .attention:
            path.addEllipse(in: CGRect(x: 8.9, y: 7.2, width: 4.8, height: 4.8))
        case .resting:
            break
        }
        return path
    }

    /// The "needs you" dot, top right, only when watching.
    static func badge(_ mood: Mood) -> Path {
        guard mood == .attention else { return Path() }
        return Path(ellipseIn: CGRect(x: 15.0, y: 0.4, width: 4.8, height: 4.8))
    }

    /// Clear space around the badge so it reads as separate from the eye.
    private static func badgeHalo(_ mood: Mood) -> Path {
        guard mood == .attention else { return Path() }
        return Path(ellipseIn: CGRect(x: 13.9, y: -0.7, width: 7.0, height: 7.0))
    }

    /// A template image for the menu bar (macOS tints it for light/dark).
    static func menuBarImage(_ mood: Mood) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setLineWidth(1.5)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            // The attention image is drawn in color (label color + orange badge),
            // so it cannot be a template; the label color still follows the menu bar.
            let ink = mood == .attention ? NSColor.labelColor.cgColor : NSColor.black.cgColor
            context.setStrokeColor(ink)
            context.setFillColor(ink)
            context.addPath(outline(mood).cgPath)
            context.strokePath()
            context.addPath(fill(mood).cgPath)
            context.fillPath()
            if mood == .attention {
                context.setBlendMode(.clear)
                context.addPath(badgeHalo(mood).cgPath)
                context.fillPath()
                context.setBlendMode(.normal)
                context.setFillColor(NSColor.systemOrange.cgColor)
                context.addPath(badge(mood).cgPath)
                context.fillPath()
            }
            return true
        }
        image.isTemplate = mood != .attention
        return image
    }
}

/// The glyph as a SwiftUI view, scaled to fit, in the current foreground style.
struct EyeGlyphView: View {
    var mood: EyeGlyph.Mood
    var lineWidth: CGFloat = 1.6
    var badgeColor: Color = .orange

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 20, size.height / 16)
            let offset = CGPoint(x: (size.width - 20 * scale) / 2, y: (size.height - 16 * scale) / 2)
            let transform = CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: scale, y: scale)
            let style = StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round, lineJoin: .round)
            var eye = context
            if mood == .attention {
                // Knock the eye out around the badge, then draw the badge in color.
                var mask = Path(CGRect(origin: .zero, size: size))
                mask.addPath(Path(ellipseIn: CGRect(x: 13.9, y: -0.7, width: 7.0, height: 7.0)).applying(transform))
                eye.clip(to: mask, style: FillStyle(eoFill: true))
            }
            eye.stroke(EyeGlyph.outline(mood).applying(transform), with: .foreground, style: style)
            eye.fill(EyeGlyph.fill(mood).applying(transform), with: .foreground)
            context.fill(EyeGlyph.badge(mood).applying(transform), with: .color(badgeColor))
        }
        .aspectRatio(20 / 16, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
