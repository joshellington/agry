import AgryCore
import AppKit
import ServiceManagement
import SwiftUI

/// A plain titled window for Settings and Help. agry is a menu bar accessory,
/// so it activates itself to bring the window forward, and keeps one window
/// per kind for the app's lifetime.
@MainActor
final class AppWindow {
    private let title: String
    private let makeContent: () -> AnyView
    private var window: NSWindow?

    init(title: String, @ViewBuilder content: @escaping () -> some View) {
        self.title = title
        makeContent = { AnyView(content()) }
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: makeContent()))
            window.title = title
            window.styleMask = [.titled, .closable]
            window.appearance = NSAppearance(named: .darkAqua)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    let controller: Controller
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var installing = false

    var body: some View {
        Form {
            Section {
                TimeoutGrid(controller: controller)
            } header: {
                Text("How long agry holds")
            } footer: {
                HStack {
                    Text("Saved to config.json.").foregroundStyle(.secondary)
                    Button("Open") { NSWorkspace.shared.open(controller.configURL) }
                        .buttonStyle(.link)
                    Spacer()
                    Button("Restore Defaults") { controller.save(.defaults) }
                        .disabled(controller.config == .defaults)
                }
                .font(.system(size: 11))
            }

            Section {
                if controller.lidInstalled {
                    Toggle("Stay awake when closed", isOn: Binding(
                        get: { controller.lidModeEnabled },
                        set: { controller.lidModeEnabled = $0 }))
                } else {
                    LabeledContent("Stay awake when closed") {
                        Button(installing ? "Waiting…" : "Set Up…") {
                            installing = true
                            Task {
                                await controller.installLidSupport()
                                installing = false
                            }
                        }
                        .disabled(installing)
                    }
                }
                Text("With the lid closed and no display on, macOS sleeps right away. This keeps the Mac awake "
                    + "while agents need it, then puts it to sleep when they're done.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if controller.lidInstalled {
                    LabeledContent("Admin rule for pmset disablesleep") {
                        Button("Remove…") { Task { await controller.uninstallLidSupport() } }
                    }
                    .font(.system(size: 12))
                }
            }

            Section {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if controller.systemNeverSleeps {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("macOS never sleeps on \(controller.onAC ? "power adapter" : "battery") by itself")
                        Text("So an idle Mac stays awake whatever agry does. To let it sleep when agents are done, "
                            + "turn off \"Prevent automatic sleeping\" in Battery › Options.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Battery Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            controller.note("launch at login failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// One row per timeout, one column per power source.
private struct TimeoutGrid: View {
    let controller: Controller

    private struct Row {
        let title: String
        let detail: String
        let path: WritableKeyPath<Timeouts, TimeInterval>
        let choices: [Int]
    }

    private let rows = [
        Row(title: "Working", detail: "At most, in case one gets stuck", path: \.workingCap, choices: [30, 60, 120, 240, 480, 720]),
        Row(title: "Needs you", detail: "Waiting on permission or an answer", path: \.blocked, choices: [5, 10, 15, 30, 60, 120]),
        Row(title: "Done or error", detail: "So you can catch up", path: \.finished, choices: [1, 2, 5, 10, 15, 30]),
        Row(title: "Remote control", detail: "At least, while you're away", path: \.remote, choices: [10, 20, 30, 60, 120, 240]),
    ]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Text("Plugged in").gridColumnAlignment(.trailing)
                Text("On battery").gridColumnAlignment(.trailing)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            ForEach(rows, id: \.title) { row in
                GridRow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title)
                        Text(row.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    picker(row, \.ac)
                    picker(row, \.battery)
                }
            }
        }
    }

    private func picker(_ row: Row, _ profile: WritableKeyPath<PolicyConfig, Timeouts>) -> some View {
        let current = Int(controller.config[keyPath: profile][keyPath: row.path] / 60)
        let choices = Set(row.choices + [current]).sorted()
        return Picker(row.title, selection: Binding(
            get: { current },
            set: { minutes in
                var config = controller.config
                config[keyPath: profile][keyPath: row.path] = TimeInterval(minutes * 60)
                controller.save(config)
            }
        )) {
            ForEach(choices, id: \.self) { Text(Theme.longDuration(TimeInterval($0 * 60))).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }
}
