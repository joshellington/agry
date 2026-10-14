import Foundation
import Sparkle

/// Checks agry.dev/appcast.xml for new versions and installs them (Sparkle).
/// Inactive unless the bundle names a feed, so a bare `swift run` never updates.
@MainActor
final class Updater {
    private let controller: SPUStandardUpdaterController?

    init() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            controller = nil
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var isAvailable: Bool { controller != nil }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// "0.2.0 (41)", from the bundle.
    static var versionDescription: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}
