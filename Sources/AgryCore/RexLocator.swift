import Foundation

/// Where to look for the `rex` CLI. GUI apps do not inherit the shell PATH, and
/// Rex only puts `rex` on PATH inside its own terminals (via `REX_BIN_DIR`).
public enum RexLocator {
    /// Rex 0.1.0-preview.17 and later install the server per user, outside the
    /// app bundle. `Current` is the running server; a newer build may be staged
    /// beside it in a numbered folder until the server restarts.
    public static func versionsDirectory(home: String) -> String {
        "\(home)/Library/Application Support/com.superlogical.rex/RexServer/Versions"
    }

    /// Candidate paths, best first. `versionNames` lists the entries of
    /// `versionsDirectory(home:)`.
    public static func candidates(home: String, override: String?, versionNames: [String]) -> [String] {
        var paths: [String] = []
        if let override { paths.append(override) }

        let binary = "Rex Server.app/Contents/MacOS/rex"
        let versions = versionsDirectory(home: home)
        let builds = versionNames.compactMap(Int.init).sorted(by: >).map(String.init)
        for name in (versionNames.contains("Current") ? ["Current"] : []) + builds {
            paths.append("\(versions)/\(name)/\(binary)")
        }

        // Older Rex builds shipped the server inside the app bundle.
        for app in ["Rex Beta.app", "Rex.app"] {
            paths.append("/Applications/\(app)/Contents/Helpers/\(binary)")
        }
        paths += [
            "\(home)/.local/bin/rex",
            "/opt/homebrew/bin/rex",
            "/usr/local/bin/rex",
        ]
        return paths
    }
}
