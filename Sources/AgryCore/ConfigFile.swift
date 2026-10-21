import Foundation

/// The user-editable config file. Values are minutes; any omitted value keeps
/// its default, so a file can override a single timeout.
public struct ConfigFile: Codable, Equatable, Sendable {
    public struct Profile: Codable, Equatable, Sendable {
        public var workingCapMinutes: Double?
        public var blockedMinutes: Double?
        public var finishedMinutes: Double?
        public var remoteMinutes: Double?

        func applied(to base: Timeouts) -> Timeouts {
            Timeouts(
                workingCap: workingCapMinutes.map { $0 * 60 } ?? base.workingCap,
                blocked: blockedMinutes.map { $0 * 60 } ?? base.blocked,
                finished: finishedMinutes.map { $0 * 60 } ?? base.finished,
                remote: remoteMinutes.map { $0 * 60 } ?? base.remote)
        }

        init(_ timeouts: Timeouts) {
            workingCapMinutes = timeouts.workingCap / 60
            blockedMinutes = timeouts.blocked / 60
            finishedMinutes = timeouts.finished / 60
            remoteMinutes = timeouts.remote / 60
        }
    }

    public var ac: Profile?
    public var battery: Profile?

    public var policy: PolicyConfig {
        let base = PolicyConfig.defaults
        return PolicyConfig(
            ac: ac?.applied(to: base.ac) ?? base.ac,
            battery: battery?.applied(to: base.battery) ?? base.battery)
    }

    public init(ac: Profile? = nil, battery: Profile? = nil) {
        self.ac = ac
        self.battery = battery
    }

    /// Every value written out, as the settings window saves it.
    public init(policy: PolicyConfig) {
        self.init(ac: Profile(policy.ac), battery: Profile(policy.battery))
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)) ?? Data("{}".utf8)
    }

    public static func parse(_ data: Data) throws -> ConfigFile {
        try JSONDecoder().decode(ConfigFile.self, from: data)
    }

    /// The defaults written out in full, as a starting point for editing.
    public static func defaultsJSON() -> Data {
        ConfigFile(policy: .defaults).encoded()
    }
}
