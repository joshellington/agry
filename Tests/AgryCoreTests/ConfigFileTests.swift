import Foundation
import Testing
@testable import AgryCore

@Suite struct ConfigFileTests {
    @Test func emptyFileKeepsDefaults() throws {
        #expect(try ConfigFile.parse(Data("{}".utf8)).policy == .defaults)
    }

    @Test func singleOverrideKeepsOtherDefaults() throws {
        let policy = try ConfigFile.parse(Data(#"{"battery":{"remoteMinutes":45}}"#.utf8)).policy
        #expect(policy.battery.remote == 45 * 60)
        #expect(policy.battery.blocked == PolicyConfig.defaults.battery.blocked)
        #expect(policy.ac == PolicyConfig.defaults.ac)
    }

    @Test func defaultsRoundTrip() throws {
        #expect(try ConfigFile.parse(ConfigFile.defaultsJSON()).policy == .defaults)
    }

    @Test func malformedFileThrows() {
        #expect(throws: (any Error).self) { try ConfigFile.parse(Data(#"{"ac":{"blockedMinutes":"ten"}}"#.utf8)) }
    }
}
