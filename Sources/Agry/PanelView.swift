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

    /// Spoken-style duration for the stay-awake picker: "45m", "1h 30m", "∞".
    static func longDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "∞" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
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
    /// The agent whose details are showing, if any (a drill-in page).
    @State var selected: String?
    /// Snapshots cannot render ScrollView, so they lay every row out flat.
    var allowsScrolling = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(controller: controller)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
            Divider().opacity(0.5)
            Group {
                if let row = selectedRow {
                    AgentDetailPage(row: row, controller: controller) { navigate(to: nil) }
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)).combined(with: .opacity))
                } else {
                    AgentList(controller: controller, allowsScrolling: allowsScrolling) { navigate(to: $0) }
                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)).combined(with: .opacity))
                }
            }
            .padding(.vertical, 10)
            .clipped()
            Divider().opacity(0.5)
            StayAwakeSection(controller: controller)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
            LidSection(controller: controller)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            Divider().opacity(0.5)
            FooterView(controller: controller)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: Theme.width)
        .tint(Theme.accent)
    }

    /// Falls back to the list when the selected agent goes away.
    private var selectedRow: AgentRow? {
        selected.flatMap { id in controller.rows.first { $0.id == id } }
    }

    private func navigate(to id: String?) {
        withAnimation(.snappy(duration: 0.25)) { selected = id }
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

private struct AgentList: View {
    let controller: Controller
    let allowsScrolling: Bool
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "Agents").padding(.horizontal, 16)
            if controller.rows.allSatisfy(\.isManual) {
                Text(controller.rexConnected ? "No programs reporting status." : "Waiting for Rex…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else {
                // Countdown text refreshes on a slow tick, only while the panel is open.
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    let list = VStack(spacing: 0) {
                        // A manual hold is shown in the Stay awake section instead.
                        ForEach(controller.rows.filter { !$0.isManual }) { row in
                            AgentRowView(row: row, now: context.date) { open(row.id) }
                        }
                    }
                    .padding(.horizontal, 6)
                    if allowsScrolling && controller.rows.count > 7 {
                        ScrollView { list }
                            .scrollBounceBehavior(.basedOnSize)
                            .frame(height: 330)
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
    let open: () -> Void
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
                    if row.isRemote { RemoteMark() }
                    Spacer(minLength: 4)
                    HoldBadge(row: row, now: now)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .opacity(hovering ? 1 : 0)
                }
                Text(row.summaryLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !row.children.isEmpty {
                    Text("↳ \(row.children.count == 1 ? row.children[0].title : "\(row.children.count) subagents")")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? AnyShapeStyle(.quaternary.opacity(0.7)) : AnyShapeStyle(.clear)))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
    }
}

private struct RemoteMark: View {
    var body: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .help("Away with remote control on: holding longer so you can reply from your phone")
    }
}

extension AgentRow {
    var summaryLine: String {
        var parts = [Theme.label(state, kind: kind)]
        if let message, !message.isEmpty { parts.append(message) }
        return parts.joined(separator: " · ")
    }
}

/// One agent's details, shown in place of the list with a back button.
private struct AgentDetailPage: View {
    let row: AgentRow
    let controller: Controller
    let back: () -> Void
    @State private var copied = false
    @State private var showOutcome: RexMonitor.ShowOutcome?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 12) {
                Button(action: back) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                        Text("AGENTS").font(.system(size: 9.5, weight: .semibold, design: .monospaced)).tracking(1.4)
                    }
                    .foregroundStyle(Theme.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(alignment: .center, spacing: 10) {
                    StateDot(state: row.state, active: row.holdUntil != nil)
                    Text(row.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    if row.isRemote { RemoteMark() }
                    Spacer(minLength: 4)
                    HoldBadge(row: row, now: now)
                }

                if let message = row.message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 11.5))
                        .lineLimit(8)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                }

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                    fact("State", "\(Theme.label(row.state, kind: row.kind)) · for \(Theme.duration(row.since, now))")
                    fact("Holding", holding(now))
                    fact("Remote", remote)
                    if let cwd = row.cwd { fact("Project", (cwd as NSString).abbreviatingWithTildeInPath) }
                    fact("Source", [row.origin.label, row.pid.map { "pid \($0)" }].compactMap { $0 }.joined(separator: " · "))
                }

                if !row.children.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        SectionLabel(text: "Subagents")
                        ForEach(row.children) { child in
                            HStack(spacing: 8) {
                                StateDot(state: child.state, active: child.holdUntil != nil)
                                Text(child.title).font(.system(size: 11.5)).lineLimit(1)
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
                        PillButton(title: "Show in Rex", compact: true) {
                            Task { showOutcome = await controller.showInRex(row) }
                        }
                    }
                    if row.holdUntil != nil {
                        PillButton(title: row.isManual ? "Stop hold" : "Let it sleep", compact: true) { controller.dismiss(row) }
                            .help("Stop this agent holding the Mac awake until its state changes")
                    }
                    PillButton(title: copied ? "Copied" : "Copy", compact: true) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(copyText(now), forType: .string)
                        copied = true
                    }
                }

                if showOutcome == .needsRemoteControl {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "info.circle").font(.system(size: 10))
                        Text("Rex focused the pane, but switching sessions needs Remote Control on in Rex.")
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Rex Settings") { RexMonitor.openRemoteControlSettings() }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent)
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                } else if showOutcome == .unavailable {
                    Text("Couldn't reach the Rex app.").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func fact(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(key.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func holding(_ now: Date) -> String {
        if row.isDismissed { return "No · you let it sleep" }
        guard let until = row.holdUntil else { return "No · \(row.reason)" }
        if until == .distantFuture { return "Until you stop it" }
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

    private func copyText(_ now: Date) -> String {
        var lines = ["\(row.name) — \(Theme.label(row.state, kind: row.kind))"]
        if let message = row.message { lines.append(message) }
        lines.append("holding: \(holding(now))")
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

// MARK: Stay awake

/// Pick a duration on a stepped slider and start; while a hold runs, the
/// section turns into a countdown with extend and stop.
private struct StayAwakeSection: View {
    let controller: Controller
    @AppStorage("manualHoldStop") private var storedIndex = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Stay awake")
            TimelineView(.periodic(from: .now, by: 15)) { context in
                if let hold = controller.manualHold {
                    active(hold, now: context.date)
                } else {
                    picker(now: context.date)
                }
            }
        }
    }

    private var stops: [TimeInterval?] { ManualHold.stops(onAC: controller.onAC) }
    private var index: Int { min(max(storedIndex, 0), stops.count - 1) }

    private func picker(now: Date) -> some View {
        let duration = stops[index]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Theme.longDuration(duration))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                Text(duration.map { "until \(now.addingTimeInterval($0).formatted(date: .omitted, time: .shortened))" }
                     ?? "until you stop it")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                PillButton(title: "Start", prominent: true, compact: true) {
                    controller.holdManually(for: duration)
                }
            }
            StepSlider(count: stops.count, index: Binding(get: { index }, set: { storedIndex = $0 }),
                       endLabels: (Theme.longDuration(stops.first!), Theme.longDuration(stops.last!)))
        }
    }

    private func active(_ hold: (since: Date, until: Date), now: Date) -> some View {
        let open = hold.until == .distantFuture
        let total = hold.until.timeIntervalSince(hold.since)
        let progress = open || total <= 0 ? 1 : max(0, min(1, hold.until.timeIntervalSince(now) / total))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(open ? "Awake until you stop it" : "Awake until \(hold.until.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12.5, weight: .medium))
                Spacer()
                if !open {
                    Text("\(Theme.duration(now, hold.until)) left")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Theme.accent).frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 4)
            HStack(spacing: 6) {
                if !open {
                    PillButton(title: "+15m", compact: true) { controller.extendManualHold(by: 15 * 60) }
                    PillButton(title: "+1h", compact: true) { controller.extendManualHold(by: 3600) }
                }
                Spacer()
                PillButton(title: "Stop", compact: true) { controller.cancelManualHold() }
            }
        }
    }
}

/// A slider that snaps to evenly spaced stops, drawn to match the panel.
private struct StepSlider: View {
    let count: Int
    @Binding var index: Int
    let endLabels: (String, String)

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                let inset: CGFloat = 7
                let width = geo.size.width - inset * 2
                let step = count > 1 ? width / CGFloat(count - 1) : 0
                let x = inset + step * CGFloat(index)
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 4).padding(.horizontal, inset)
                    Capsule().fill(Theme.accent).frame(width: max(0, x - inset), height: 4).offset(x: inset)
                    ForEach(0..<count, id: \.self) { i in
                        Circle()
                            .fill(i <= index ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                            .frame(width: 3, height: 3)
                            .offset(x: inset + step * CGFloat(i) - 1.5)
                    }
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                        .frame(width: 14, height: 14)
                        .offset(x: x - 7)
                }
                .frame(height: 18)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard step > 0 else { return }
                    let raw = ((value.location.x - inset) / step).rounded()
                    let next = Int(min(max(raw, 0), CGFloat(count - 1)))
                    if next != index { index = next }
                })
            }
            .frame(height: 18)
            HStack {
                Text(endLabels.0)
                Spacer()
                Text(endLabels.1)
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.tertiary)
        }
        .accessibilityElement()
        .accessibilityLabel("Stay awake duration")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: index = min(index + 1, count - 1)
            case .decrement: index = max(index - 1, 0)
            @unknown default: break
            }
        }
    }
}

// MARK: Lid closed

private struct LidSection: View {
    let controller: Controller
    @State private var installing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Lid closed")
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
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
                    PillButton(title: installing ? "Waiting…" : "Set up", prominent: true, compact: true) {
                        installing = true
                        Task {
                            await controller.installLidSupport()
                            installing = false
                        }
                    }
                    .disabled(installing)
                }
            }
        }
    }

    private var title: String {
        guard controller.lidInstalled else { return "Stay awake with the lid shut" }
        guard controller.lidModeEnabled else { return "Off" }
        return controller.lidVerdict.isArmed ? "Armed" : "Standing by"
    }

    private var detail: String {
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
