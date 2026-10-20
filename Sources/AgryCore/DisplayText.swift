import Foundation

/// Cleans program-supplied text (OSC 7501 `msg` and `title`) before agry shows
/// it outside the terminal. The spec asks terminals to disarm direction
/// overrides and other invisible formatting there, so a message cannot
/// reorder or hide what the panel shows.
public enum DisplayText {
    public static func sanitize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where keep(scalar) {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    private static func keep(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control:
            return false
        case .format:
            // The zero-width joiner holds emoji sequences together.
            return scalar == "\u{200D}"
        default:
            return true
        }
    }
}
