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

    /// Compact duration between two dates: "45s", "12m", "2h05".
    static func duration(_ from: Date, _ to: Date) -> String {
        let seconds = max(0, Int(to.timeIntervalSince(from)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h\(String(format: "%02d", minutes % 60))"
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
    var initiallyExpanded: String?
    /// Snapshots cannot render ScrollView, so they lay every row out flat.
    var allowsScrolling = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(controller: controller)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
            Divider().opacity(0.5)
            AgentsSection(controller: controller, allowsScrolling: allowsScrolling, expanded: initiallyExpanded)
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
                    .frame(width: 24)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title(mood))
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

    private func title(_ mood: EyeGlyph.Mood) -> String {
        switch mood {
        case .awake: "Awake"
        case .attention: "Needs you"
        case .resting: "Resting"
        }
    }

    private var subtitle: String {
        let blocked = controller.rows.filter { $0.state == .blocked && $0.holdUntil != nil }
        if let first = blocked.first {
            let what = "\(first.name) · \(Theme.label(first.state, kind: first.kind))"
            return blocked.count > 1 ? "\(what) (+\(blocked.count - 1))" : what
        }
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
    let allowsScrolling: Bool
    /// The one expanded row, if any. Clicking a row toggles it.
    @State var expanded: String?

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
                    let list = VStack(spacing: 2) {
                        ForEach(controller.rows) { row in
                            AgentRowView(row: row, now: context.date, controller: controller,
                                         isExpanded: expanded == row.id) {
                                withAnimation(.snappy(duration: 0.22)) {
                                    expanded = expanded == row.id ? nil : row.id
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    // Scroll only when the list would make the panel unwieldy.
                    if allowsScrolling && (controller.rows.count > 6 || expanded != nil && controller.rows.count > 3) {
                        ScrollView { list }.frame(height: 360)
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
    let controller: Controller
    let isExpanded: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
                .contentShape(Rectangle())
                .onTapGesture(perform: toggle)
            if isExpanded {
                AgentDetailView(row: row, now: now, controller: controller)
                    .padding(.leading, 17)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(background))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(isExpanded ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)))
        .onHover { hovering = $0 }
    }

    private var background: AnyShapeStyle {
        if isExpanded { return AnyShapeStyle(.quaternary.opacity(0.45)) }
        return hovering ? AnyShapeStyle(.quaternary.opacity(0.7)) : AnyShapeStyle(.clear)
    }

    private var summary: some View {
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
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .opacity(hovering || isExpanded ? 1 : 0)
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? 6 : 1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: isExpanded)
                if !row.children.isEmpty && !isExpanded {
                    Text("↳ \(row.children.count == 1 ? row.children[0].title : "\(row.children.count) subagents")")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var detail: String {
        var parts = [Theme.label(row.state, kind: row.kind)]
        if let message = row.message, !message.isEmpty { parts.append(message) }
        return parts.joined(separator: " · ")
    }
}

/// The expanded part of a row: facts on the left in a small grid, subagents,
/// then actions.
private struct AgentDetailView: View {
    let row: AgentRow
    let now: Date
    let controller: Controller
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 5) {
                fact("State", "\(Theme.label(row.state, kind: row.kind)) · for \(Theme.duration(row.since, now))")
                fact("Holding", holding)
                fact("Remote", remote)
                if let cwd = row.cwd { fact("Project", (cwd as NSString).abbreviatingWithTildeInPath) }
                fact("Source", [row.origin.label, row.pid.map { "pid \($0)" }].compactMap { $0 }.joined(separator: " · "))
            }

            if !row.children.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "Subagents")
                    ForEach(row.children) { child in
                        HStack(spacing: 8) {
                            StateDot(state: child.state, active: child.holdUntil != nil)
                            Text(child.title).font(.system(size: 11)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(Theme.label(child.state, kind: nil))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                if case .rex = row.origin {
                    PillButton(title: "Show in Rex", compact: true) { controller.showInRex(row) }
                }
                if row.holdUntil != nil {
                    PillButton(title: row.isManual ? "Cancel hold" : "Let it sleep", compact: true) { controller.dismiss(row) }
                        .help("Stop this agent holding the Mac awake until its state changes")
                }
                PillButton(title: copied ? "Copied" : "Copy", compact: true) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(copyText, forType: .string)
                    copied = true
                }
            }
        }
        .font(.system(size: 11))
    }

    private func fact(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(key.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.tertiary)
                .gridColumnAlignment(.leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var holding: String {
        if row.isDismissed { return "No · you let it sleep" }
        guard let until = row.holdUntil else { return "No · \(row.reason)" }
        if until == .distantFuture { return "Until you turn it off" }
        if row.isHoldingForWork {
            let who = row.state == .working ? "" : "subagents "
            return "While \(who)working (cap at \(until.formatted(date: .omitted, time: .shortened)))"
        }
        return "Until \(until.formatted(date: .omitted, time: .shortened)) · \(Theme.duration(now, until)) left"
    }

    private var remote: String {
        guard row.remoteControlEnabled else { return "Remote control off" }
        if row.isRemote { return "On · you're away, holding longer for phone replies" }
        return "On · you're here, normal timeouts"
    }

    private var copyText: String {
        var lines = ["\(row.name) — \(Theme.label(row.state, kind: row.kind))"]
        if let message = row.message { lines.append(message) }
        lines.append("holding: \(holding)")
        lines.append("remote: \(remote)")
        if let cwd = row.cwd { lines.append("project: \(cwd)") }
        lines.append("source: \(row.origin.label)\(row.pid.map { " pid \($0)" } ?? "")")
        for child in row.children { lines.append("  ↳ \(child.title): \(child.state.rawValue)") }
        return lines.joined(separator: "\n")
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
        if row.isHoldingForWork { return "live" }
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
    var compact = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: compact ? 10.5 : 11.5, weight: .medium, design: .monospaced))
                .frame(maxWidth: compact ? nil : .infinity)
                .padding(.horizontal, compact ? 9 : 0)
                .padding(.vertical, compact ? 4 : 5)
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
