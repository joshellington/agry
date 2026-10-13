import AgryCore
import ServiceManagement
import SwiftUI

/// Visual language: night-violet accent, monospaced micro-labels, quiet rows
/// that only light up on hover. State colors are shared by dots and chips.
enum Theme {
    static let accent = Color(red: 0.56, green: 0.49, blue: 0.98)
    static let width: CGFloat = 340

    static func color(_ state: ProgramState) -> Color {
        switch state {
        case .working: accent
        case .blocked: .orange
        case .done: .mint
        case .error: .red
        case .idle: .secondary
        }
    }

    static func label(_ state: ProgramState, kind: String?) -> String {
        switch state {
        case .blocked: kind.map { "needs \($0)" } ?? "blocked"
        default: state.rawValue
        }
    }
}

struct PanelView: View {
    let controller: Controller

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(controller: controller)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
            Divider().opacity(0.5)
            AgentsSection(controller: controller)
                .padding(.vertical, 10)
            Divider().opacity(0.5)
            ControlsSection(controller: controller)
                .padding(16)
            Divider().opacity(0.5)
            FooterView(controller: controller)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: Theme.width)
        .tint(Theme.accent)
    }
}

// MARK: Header

private struct HeaderView: View {
    let controller: Controller

    var body: some View {
        let mood = controller.mood
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle().fill(mood == .resting ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Theme.accent.opacity(0.18)))
                EyeGlyphView(mood: mood, lineWidth: 1.4)
                    .foregroundStyle(mood == .resting ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.accent))
                    .frame(width: 22)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(mood == .resting ? "Resting" : "Awake")
                    .font(.system(size: 16, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .topTrailing) { StatusChips(controller: controller) }
    }

    private var subtitle: String {
        let holding = controller.rows.filter { $0.holdUntil != nil }
        guard !holding.isEmpty else { return "Sleep behaves normally" }
        let noun = holding.count == 1 ? "1 agent" : "\(holding.count) agents"
        if holding.contains(where: { $0.state == .working }) { return "\(noun) holding · work in progress" }
        guard let until = holding.compactMap(\.holdUntil).max(), until != .distantFuture else { return "\(noun) holding" }
        return "\(noun) holding · until \(until.formatted(date: .omitted, time: .shortened))"
    }
}

private struct StatusChips: View {
    let controller: Controller

    var body: some View {
        HStack(spacing: 4) {
            if controller.thermal >= .fair {
                Chip(symbol: "thermometer.medium", text: controller.thermal >= .serious ? "hot" : "warm",
                     tint: controller.thermal >= .serious ? .red : .orange)
            }
            if controller.onAC {
                Chip(symbol: "bolt.fill", text: "AC")
            } else {
                Chip(symbol: "battery.50", text: controller.batteryPercent.map { "\($0)%" } ?? "battery")
            }
            Chip(symbol: nil, text: "rex", dot: controller.rexConnected ? .green : .secondary)
        }
    }
}

private struct Chip: View {
    var symbol: String?
    var text: String
    var tint: Color = .secondary
    var dot: Color?

    var body: some View {
        HStack(spacing: 3) {
            if let dot { Circle().fill(dot).frame(width: 5, height: 5) }
            if let symbol { Image(systemName: symbol).font(.system(size: 8, weight: .bold)) }
            Text(text).font(.system(size: 9.5, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(.quaternary.opacity(0.6)))
    }
}

// MARK: Agents

struct SectionLabel: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(.tertiary)
    }
}

private struct AgentsSection: View {
    let controller: Controller

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "Agents").padding(.horizontal, 16)
            if controller.rows.isEmpty {
                Text(controller.rexConnected ? "No programs reporting status." : "Waiting for Rex…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else {
                // Countdown text refreshes on a slow tick, only while the panel is open.
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    let list = VStack(spacing: 0) {
                        ForEach(controller.rows) { row in
                            AgentRowView(row: row, now: context.date)
                        }
                    }
                    .padding(.horizontal, 6)
                    // Scroll only when the list would make the panel unwieldy.
                    if controller.rows.count > 6 {
                        ScrollView { list }.frame(height: 340)
                    } else {
                        list
                    }
                }
            }
        }
    }
}

private struct AgentRowView: View {
    let row: AgentRow
    let now: Date
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StateDot(state: row.state, active: row.holdUntil != nil)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if row.isRemote {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .help("Away with remote control on: holding longer so you can reply from your phone")
                    }
                    Spacer(minLength: 4)
                    HoldBadge(row: row, now: now)
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !row.childTitles.isEmpty {
                    Text("↳ \(row.childTitles.count == 1 ? row.childTitles[0] : "\(row.childTitles.count) subagents")")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .help(row.childTitles.joined(separator: "\n"))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? AnyShapeStyle(.quaternary.opacity(0.7)) : AnyShapeStyle(.clear)))
        .onHover { hovering = $0 }
        .help(row.reason)
    }

    private var detail: String {
        var parts = [Theme.label(row.state, kind: row.kind)]
        if let message = row.message, !message.isEmpty { parts.append(message) }
        return parts.joined(separator: " · ")
    }
}

struct StateDot: View {
    let state: ProgramState
    let active: Bool
    @State private var pulse = false

    var body: some View {
        let color = active ? Theme.color(state) : Color.secondary.opacity(0.5)
        ZStack {
            if state == .working && active {
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 1.5)
                    .scaleEffect(pulse ? 2.1 : 1)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
                    .onAppear { pulse = true }
            }
            Circle().fill(color)
        }
        .frame(width: 7, height: 7)
    }
}

private struct HoldBadge: View {
    let row: AgentRow
    let now: Date

    var body: some View {
        if let text {
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(row.holdUntil == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
        }
    }

    private var text: String? {
        guard let until = row.holdUntil else { return row.state == .idle ? nil : "released" }
        if until == .distantFuture { return "∞" }
        if row.state == .working && !row.isManual { return "live" }
        let minutes = max(1, Int(until.timeIntervalSince(now) / 60))
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h\(String(format: "%02d", minutes % 60))"
    }
}

// MARK: Controls

private struct ControlsSection: View {
    let controller: Controller
    @State private var installing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionLabel(text: "Stay awake")
                    Spacer()
                    if controller.hasManualHold {
                        Button("Cancel") { controller.cancelManualHold() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                }
                HStack(spacing: 6) {
                    ForEach([("15m", 15), ("1h", 60), ("3h", 180), ("∞", 0)], id: \.1) { title, minutes in
                        PillButton(title: title) {
                            controller.holdManually(for: minutes == 0 ? nil : TimeInterval(minutes * 60))
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Lid closed")
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(lidTitle).font(.system(size: 12, weight: .medium))
                        Text(lidDetail).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if controller.lidInstalled {
                        Toggle("", isOn: Binding(
                            get: { controller.lidModeEnabled },
                            set: { controller.lidModeEnabled = $0 }))
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                    } else {
                        PillButton(title: installing ? "Waiting…" : "Set up", prominent: true) {
                            installing = true
                            Task {
                                await controller.installLidSupport()
                                installing = false
                            }
                        }
                        .frame(width: 84)
                        .disabled(installing)
                    }
                }
            }
        }
    }

    private var lidTitle: String {
        guard controller.lidInstalled else { return "Stay awake with the lid shut" }
        guard controller.lidModeEnabled else { return "Off" }
        return controller.lidVerdict.isArmed ? "Armed" : "Standing by"
    }

    private var lidDetail: String {
        guard controller.lidInstalled else { return "Needs your password once" }
        switch controller.lidVerdict {
        case .armed: return controller.lidClosed ? "Lid is closed, still awake" : "Safe to close the lid"
        case .disarmed(let reason): return reason.prefix(1).capitalized + reason.dropFirst()
        }
    }
}

private struct PillButton: View {
    let title: String
    var prominent = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .foregroundStyle(prominent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
                .background(RoundedRectangle(cornerRadius: 7).fill(fill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var fill: AnyShapeStyle {
        if prominent { return AnyShapeStyle(Theme.accent.opacity(hovering ? 0.3 : 0.18)) }
        return hovering ? AnyShapeStyle(Theme.accent.opacity(0.22)) : AnyShapeStyle(.quaternary.opacity(0.6))
    }
}

// MARK: Footer

private struct FooterView: View {
    let controller: Controller
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showingHelp = false

    var body: some View {
        HStack(spacing: 8) {
            Text("agry")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                showingHelp.toggle()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("What the colors and states mean")
            .popover(isPresented: $showingHelp, arrowEdge: .leading) {
                HelpView(config: controller.config, onAC: controller.onAC)
            }
            Menu {
                Toggle("Launch at Login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                Divider()
                Button("Edit Config…") { NSWorkspace.shared.open(controller.configURL) }
                Button("Reload Config") { controller.reloadConfig() }
                Divider()
                Button("Open Event Log") { NSWorkspace.shared.open(controller.debugDirectory.appending(path: "events.log")) }
                Button("Copy State") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(controller.stateDescription(), forType: .string)
                }
                if controller.lidInstalled {
                    Divider()
                    Button("Remove Lid-Closed Support…") { Task { await controller.uninstallLidSupport() } }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit agry")
        }
        .foregroundStyle(.secondary)
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
