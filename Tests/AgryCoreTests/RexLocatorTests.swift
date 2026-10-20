import Testing
@testable import AgryCore

@Suite struct RexLocatorTests {
    private let home = "/Users/dev"
    private var versions: String { "\(home)/Library/Application Support/com.superlogical.rex/RexServer/Versions" }
    private let binary = "Rex Server.app/Contents/MacOS/rex"

    @Test func overrideComesFirst() {
        let paths = RexLocator.candidates(home: home, override: "/tmp/rex", versionNames: [])
        #expect(paths.first == "/tmp/rex")
    }

    @Test func runningServerBeforeStagedVersions() {
        let paths = RexLocator.candidates(home: home, override: nil, versionNames: ["1310", "Current", "1324"])
        #expect(Array(paths.prefix(3)) == [
            "\(versions)/Current/\(binary)",
            "\(versions)/1324/\(binary)",
            "\(versions)/1310/\(binary)",
        ])
    }

    @Test func versionsSortNumerically() {
        let paths = RexLocator.candidates(home: home, override: nil, versionNames: ["999", "1000"])
        #expect(paths.first == "\(versions)/1000/\(binary)")
    }

    @Test func ignoresStrayEntries() {
        let paths = RexLocator.candidates(home: home, override: nil, versionNames: [".DS_Store", "tmp"])
        #expect(!paths.contains { $0.hasPrefix(versions) })
    }

    @Test func keepsLegacyAppBundlePath() {
        let paths = RexLocator.candidates(home: home, override: nil, versionNames: [])
        #expect(paths.contains("/Applications/Rex Beta.app/Contents/Helpers/Rex Server.app/Contents/MacOS/rex"))
    }
}
