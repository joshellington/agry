import AgryCore
import Foundation

/// Keeps the Mac awake with the lid closed via `pmset disablesleep`.
///
/// That flag is system-wide and needs root, so agry installs a sudoers rule
/// allowing exactly `pmset -a disablesleep 0|1` and nothing else. agry only
/// ever clears the flag if it set it (a marker file records that), so it does
/// not fight other tools, and a crash is repaired on the next launch.
@MainActor
final class LidGuard {
    static let sudoersPath = "/etc/sudoers.d/agry"

    private(set) var isArmed = false
    var onLog: ((String) -> Void)?

    private let marker: URL

    init(stateDirectory: URL) {
        marker = stateDirectory.appending(path: "disablesleep-armed")
    }

    var isInstalled: Bool { FileManager.default.fileExists(atPath: LidGuard.sudoersPath) }

    /// Clears a flag left set by a previous run that did not exit cleanly.
    func recover() {
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        onLog?("lid: clearing disablesleep left by previous run")
        isArmed = true
        set(armed: false)
    }

    func set(armed: Bool) {
        guard armed != isArmed, isInstalled else { return }
        isArmed = armed
        if armed {
            try? FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: marker.path, contents: nil)
        }
        let ok = LidGuard.runPmset(armed)
        onLog?("lid: disablesleep \(armed ? 1 : 0) \(ok ? "ok" : "FAILED")")
        if !ok { isArmed = !armed }
        if !isArmed { try? FileManager.default.removeItem(at: marker) }
    }

    /// Re-applies the flag if something else cleared it while agry has it armed
    /// (another keep-awake tool exiting, for example, resets it to 0).
    func reassertIfCleared() {
        guard isArmed, isInstalled else { return }
        let pmset = Process()
        let pipe = Pipe()
        pmset.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        pmset.arguments = ["-g"]
        pmset.standardOutput = pipe
        pmset.standardError = FileHandle.nullDevice
        guard (try? pmset.run()) != nil else { return }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        pmset.waitUntilExit()
        guard PmsetOutput.sleepDisabled(from: output) == false else { return }
        let ok = LidGuard.runPmset(true)
        onLog?("lid: disablesleep was cleared by something else; re-applied \(ok ? "ok" : "FAILED")")
    }

    /// Asks for an admin password (system dialog) and installs the sudoers rule.
    func install() async -> Bool {
        let rule = "\(NSUserName()) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n"
        return await LidGuard.runPrivileged("""
            set -e
            tmp=$(/usr/bin/mktemp)
            /usr/bin/printf '%s' '\(rule)' > "$tmp"
            /usr/sbin/visudo -cf "$tmp"
            /usr/bin/install -m 0440 -o root -g wheel "$tmp" \(LidGuard.sudoersPath)
            /bin/rm -f "$tmp"
            """)
    }

    func uninstall() async -> Bool {
        set(armed: false)
        return await LidGuard.runPrivileged("/bin/rm -f \(LidGuard.sudoersPath); /usr/bin/pmset -a disablesleep 0")
    }

    /// `pmset` returns quickly; running it inline keeps ordering simple.
    private static func runPmset(_ armed: Bool) -> Bool {
        run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", armed ? "1" : "0"])
    }

    private static func runPrivileged(_ script: String) async -> Bool {
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        return await Task.detached { run("/usr/bin/osascript", ["-e", source]) }.value
    }

    nonisolated private static func run(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
