import AgryCore
import ServiceManagement
import SwiftUI

/// The one settings window: how long each state holds (editable, per power
/// source), staying awake when closed, how to read the menu bar, and launch
/// at login. Each setting sits next to its explanation.
struct SettingsView: View {
    let controller: Controller
    /// Previews lay the whole page out flat so it can be captured in one go.
    var allowsScrolling = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var installing = false

    var body: some View {
        // Taller than a laptop screen, so it scrolls within a fixed window.
        Group {
            if allowsScrolling {
                ScrollView { content }.frame(height: 740)
            } else {
                content.fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 600)
        .environment(\.colorScheme, .dark)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .top, spacing: 16) {
                SkullGlyphView(mood: .awake, lineWidth: 2).frame(width: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text("agry").font(.system(size: 18, weight: .semibold))
                    Paragraph("macOS sleeps a Mac nobody is using. agry holds that off while your agents work, "
                        + "and for a while after, so results and questions are waiting when you're back.")
                }
            }

            if controller.systemNeverSleeps {
                Callout(
                    title: "macOS is set never to sleep on \(controller.onAC ? "power adapter" : "battery")",
                    text: "So an idle Mac stays awake whatever agry does. To let it sleep when agents are done, "
                        + "turn off \"Prevent automatic sleeping\" in Battery › Options.") {
                    Button("Open Battery Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                }
            }

            SettingsSection("How long agry holds") {
                HoldTable(controller: controller)
                HStack(spacing: 6) {
                    Footnote("Saved to config.json.")
                    Button("Open") { NSWorkspace.shared.open(controller.configURL) }
                        .buttonStyle(.link)
                        .font(.system(size: 11.5))
                    Spacer()
                    Button("Restore Defaults") { controller.save(.defaults) }
                        .controlSize(.small)
                        .disabled(controller.config == .defaults)
                }
            }

            SettingsSection("Stay awake when closed") {
                HStack(alignment: .firstTextBaseline) {
                    Paragraph("With the lid closed and no display on, macOS sleeps right away, even mid-task. That "
                        + "includes turning off or unplugging your monitor while the lid is shut. A monitor that's "
                        + "only asleep or on another input still counts as on.")
                    Spacer(minLength: 24)
                    lidControl
                }
                Paragraph("With this on, agry keeps the Mac awake through that while all of these are true:")
                VStack(alignment: .leading, spacing: 6) {
                    RuleLine(symbol: "eye", text: "Something is holding.")
                    RuleLine(symbol: "thermometer.medium", text: "The Mac isn't running hot.")
                    RuleLine(symbol: "powerplug.portrait",
                             text: "It's plugged in, or above \(LidPolicy.minimumBatteryPercent)% on battery while you're away with remote control.")
                }
                .padding(.leading, 2)
                Paragraph("When they stop being true, agry puts the Mac to sleep.")
                HStack(spacing: 6) {
                    Footnote(controller.lidInstalled
                        ? "Setup added one admin rule that allows only `pmset disablesleep`."
                        : "Setup adds one admin rule that allows only `pmset disablesleep`, and asks for your password.")
                    if controller.lidInstalled {
                        Button("Remove…") { Task { await controller.uninstallLidSupport() } }
                            .buttonStyle(.link)
                            .font(.system(size: 11.5))
                    }
                }
            }

            SettingsSection("Reading the menu bar") {
                HStack(alignment: .top, spacing: 12) {
                    GlyphCard(mood: .awake, title: "Awake", detail: "Something is keeping the Mac awake.")
                    GlyphCard(mood: .attention, title: "Needs you", detail: "An agent is waiting on you.")
                    GlyphCard(mood: .resting, title: "Resting", detail: "Nothing holding; the Mac sleeps as usual.")
                }
                HStack(alignment: .firstTextBaseline, spacing: 28) {
                    MarkLine(detail: "How long it has been working") { Text("12m").monospacedDigit() }
                    MarkLine(detail: "Until agry stops holding") {
                        HStack(spacing: 3) {
                            Image(systemName: "zzz").font(.system(size: 8, weight: .semibold))
                            Text("4m").monospacedDigit()
                        }
                    }
                }
                .padding(.top, 4)
            }

            SettingsSection("General") {
                HStack {
                    Text("Launch at login").font(.system(size: 12.5))
                    Spacer()
                    Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
            }
        }
        .padding(28)
    }

    @ViewBuilder private var lidControl: some View {
        if controller.lidInstalled {
            Toggle("Stay awake when closed", isOn: Binding(
                get: { controller.lidModeEnabled },
                set: { controller.lidModeEnabled = $0 }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        } else {
            Button(installing ? "Waiting…" : "Set Up…") {
                installing = true
                Task {
                    await controller.installLidSupport()
                    installing = false
                }
            }
            .controlSize(.small)
            .disabled(installing)
        }
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

/// States down the side, power sources across, each time a menu. The current
/// power source's header is brighter.
private struct HoldTable: View {
    let controller: Controller

    private static let timeWidth: CGFloat = 104

    private struct Row {
        let mark: AnyView
        let title: String
        let detail: String
        let path: WritableKeyPath<Timeouts, TimeInterval>?
        var choices: [Int] = []
    }

    private var rows: [Row] {
        [
            Row(mark: AnyView(StatusMark(state: .working)), title: "Working",
                detail: "Holds while running, up to this long in case one gets stuck.",
                path: \.workingCap, choices: [30, 60, 120, 240, 480, 720]),
            Row(mark: AnyView(StatusMark(state: .blocked)), title: "Needs you",
                detail: "Waiting on permission or an answer.", path: \.blocked, choices: [5, 10, 15, 30, 60, 120]),
            Row(mark: AnyView(HStack(spacing: 2) { StatusMark(state: .done); StatusMark(state: .error) }), title: "Done or error",
                detail: "Finished or failed, so you can catch up.", path: \.finished, choices: [1, 2, 5, 10, 15, 30]),
            Row(mark: AnyView(StatusMark(state: .idle)), title: "Idle", detail: "At rest. Never holds.", path: nil),
            Row(mark: AnyView(Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 10)).foregroundStyle(.secondary)),
                title: "Remote control",
                detail: "At least this long while you're away with remote control on, so replies from your phone can land. "
                    + "Touching the Mac ends it.",
                path: \.remote, choices: [10, 20, 30, 60, 120, 240]),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Spacer()
                header("Plugged in", current: controller.onAC)
                header("On battery", current: !controller.onAC)
            }
            .padding(.bottom, 6)
            ForEach(rows, id: \.title) { row($0) }
        }
    }

    private func header(_ title: String, current: Bool) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(current ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            .frame(width: Self.timeWidth, alignment: .trailing)
    }

    private func row(_ row: Row) -> some View {
        HStack(alignment: .center, spacing: 0) {
            row.mark.frame(width: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: 12.5, weight: .medium))
                Text(row.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let path = row.path {
                picker(row, path, \.ac)
                picker(row, path, \.battery)
            } else {
                Text("—").foregroundStyle(.tertiary).frame(width: Self.timeWidth, alignment: .trailing)
                Text("—").foregroundStyle(.tertiary).frame(width: Self.timeWidth, alignment: .trailing)
            }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Theme.hairline.frame(height: 1) }
    }

    private func picker(_ row: Row, _ path: WritableKeyPath<Timeouts, TimeInterval>,
                        _ profile: WritableKeyPath<PolicyConfig, Timeouts>) -> some View {
        let current = Int(controller.config[keyPath: profile][keyPath: path] / 60)
        let choices = Set(row.choices + [current]).sorted()
        return Picker(row.title, selection: Binding(
            get: { current },
            set: { minutes in
                var config = controller.config
                config[keyPath: profile][keyPath: path] = TimeInterval(minutes * 60)
                controller.save(config)
            }
        )) {
            ForEach(choices, id: \.self) { Text(Theme.longDuration(TimeInterval($0 * 60))).tag($0) }
        }
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .frame(width: Self.timeWidth, alignment: .trailing)
    }
}

private struct GlyphCard: View {
    let mood: SkullGlyph.Mood
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkullGlyphView(mood: mood, lineWidth: 1.5)
                .frame(width: 22, height: 22)
                .foregroundStyle(mood == .resting ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            Text(title).font(.system(size: 12.5, weight: .medium))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.wash))
    }
}

private struct Callout<Accessory: View>: View {
    let title: String
    let text: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.amber.opacity(0.35)))
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))
            content
        }
    }
}

private struct Paragraph: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.system(size: 11.5))
            .foregroundStyle(.tertiary)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct RuleLine: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
            Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MarkLine<Mark: View>: View {
    let detail: String
    @ViewBuilder let mark: Mark

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            mark.font(.system(size: 11.5)).foregroundStyle(.tertiary)
            Text(detail).font(.system(size: 12.5)).foregroundStyle(.secondary)
        }
    }
}
