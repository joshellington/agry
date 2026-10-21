import AgryCore
import SwiftUI

/// Visual language ("nocturnal instrument"): always dark, monochrome by
/// default. Color carries meaning only: sodium amber when something needs the
/// user, red for errors. States are told apart by shape, not hue.
enum Theme {
    static let width: CGFloat = 340
    /// Sodium-lamp amber: needs you. Also the eye's pupil.
    static let amber = Color(nsColor: EyeGlyph.attentionColor)
    static let red = Color(red: 1.0, green: 0.42, blue: 0.37)
    static let hairline = Color.white.opacity(0.08)
    static let wash = Color.white.opacity(0.05)
    static let washHover = Color.white.opacity(0.08)

    /// Compact duration between two dates: "45s", "12m", "2h05".
    static func duration(_ from: Date, _ to: Date) -> String {
        let seconds = max(0, Int(to.timeIntervalSince(from)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h\(String(format: "%02d", minutes % 60))"
    }

    /// Spoken-style duration for the keep-awake picker: "45m", "1h 30m", "∞".
    static func longDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "∞" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    static func label(_ state: ProgramState, kind: String?) -> String {
        switch state {
        case .blocked: kind.map { "Needs \($0)" } ?? "Needs you"
        case .working: "Working"
        case .done: "Done"
        case .error: "Error"
        case .idle: "Idle"
        }
    }

    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}

struct PanelView: View {
    let controller: Controller
    let navigation: PanelNavigation
    /// Snapshots cannot render ScrollView, so they lay every row out flat.
    var allowsScrolling = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(controller: controller)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
            Theme.hairline.frame(height: 1)
            Group {
                if let row = selectedRow {
                    AgentDetailPage(row: row, controller: controller) { navigate(to: nil) }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    AgentList(controller: controller, allowsScrolling: allowsScrolling) { navigate(to: $0) }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .padding(.vertical, 8)
            .clipped()
            Theme.hairline.frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                if controller.manualHold != nil {
                    ActiveHoldStrip(controller: controller)
                } else if navigation.keepAwakeOpen {
                    KeepAwakeDrawer(controller: controller) { navigation.keepAwakeOpen = false }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                LidRow(controller: controller)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Theme.hairline.frame(height: 1)
            FooterView(controller: controller, navigation: navigation)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
        }
        .frame(width: Theme.width)
        // A dark wash over the blur keeps the panel from taking on the colors
        // of whatever is behind it.
        .background(Color.black.opacity(0.28))
        // Report a definite height so the hosting panel can fit it exactly.
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.colorScheme, .dark)
        .tint(.white)
    }

    /// Falls back to the list when the selected agent goes away.
    private var selectedRow: AgentRow? {
        navigation.selected.flatMap { id in controller.rows.first { $0.id == id } }
    }

    private func navigate(to id: String?) {
        withAnimation(.snappy(duration: 0.25)) { navigation.selected = id }
    }
}

// MARK: Header

private struct HeaderView: View {
    let controller: Controller

    var body: some View {
        let mood = controller.mood
        HStack(alignment: .center, spacing: 11) {
            EyeGlyphView(mood: mood, lineWidth: 1.5)
                .foregroundStyle(mood == .resting ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title(mood))
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(mood == .attention ? AnyShapeStyle(Theme.amber) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            SystemGlyphs(controller: controller)
        }
    }

    private func title(_ mood: EyeGlyph.Mood) -> String {
        switch mood {
        case .awake: "Awake"
        case .attention: "Needs you"
        case .resting: "Resting"
        }
    }

    private var subtitle: String {
        let rows = controller.rows.filter { !$0.isManual }
        let blocked = rows.filter { $0.state == .blocked && $0.holdUntil != nil }
        if let first = blocked.first {
            let what = "\(first.name): \(Theme.label(first.state, kind: first.kind).lowercased())"
            return blocked.count > 1 ? "\(what) +\(blocked.count - 1)" : what
        }
        let working = rows.filter(\.isHoldingForWork).count
        if working > 0 { return working == 1 ? "1 agent working" : "\(working) agents working" }
        if let until = rows.compactMap(\.holdUntil).max(), until != .distantFuture {
            return "Sleep allowed after \(Theme.time(until))"
        }
        if controller.manualHold != nil { return "Kept awake by you" }
        return controller.systemNeverSleeps ? "Not holding; macOS is set never to sleep" : "Sleep works as usual"
    }
}

/// Power, heat and Rex at a glance: plain glyphs, tinted only when notable.
private struct SystemGlyphs: View {
    let controller: Controller

    var body: some View {
        HStack(spacing: 9) {
            if controller.thermal >= .fair {
                Image(systemName: "thermometer.medium")
                    .foregroundStyle(controller.thermal >= .serious ? Theme.red : Theme.amber)
                    .help(controller.thermal >= .serious ? "Running hot" : "Running warm")
            }
            if controller.onAC {
                Image(systemName: "powerplug.portrait").help("On AC power")
            } else {
                HStack(spacing: 2) {
                    Image(systemName: "battery.75percent")
                    Text(controller.batteryPercent.map { "\($0)%" } ?? "").monospacedDigit()
                }
                .help("On battery")
            }
            Image(systemName: "terminal")
                .opacity(controller.rexConnected ? 1 : 0.35)
                .help(controller.rexConnected ? "Rex connected" : "Rex not connected")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
    }
}

// MARK: Agents

private struct AgentList: View {
    let controller: Controller
    let allowsScrolling: Bool
    let open: (String) -> Void

    var body: some View {
        let rows = controller.rows.filter { !$0.isManual }
        if rows.isEmpty {
            Text(controller.rexConnected ? "No agents reporting." : "Waiting for Rex…")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        } else {
            // Times refresh on a slow tick, only while the panel is open.
            TimelineView(.periodic(from: .now, by: 15)) { context in
                let list = VStack(spacing: 1) {
                    ForEach(rows) { row in
                        AgentRowView(row: row, now: context.date) { open(row.id) }
                    }
                }
                .padding(.horizontal, 6)
                if allowsScrolling && rows.count > 7 {
                    ScrollView { list }
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(height: 360)
                } else {
                    list
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
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            StatusMark(state: row.state, holding: row.holdUntil != nil, progress: row.progress)
                .frame(width: 12)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(row.holdUntil == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    if row.isRemote { RemoteMark() }
                    Spacer(minLength: 6)
                    TimeTag(row: row, now: now)
                }
                StatusLine(row: row)
                    .lineLimit(1)
                if !row.children.isEmpty {
                    Text(row.children.count == 1 ? row.children[0].title : "\(row.children.count) subagents")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Theme.washHover : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
    }
}

/// "Needs permission  Allow rm…", with the need in amber; working rows show
/// just their message since the spinner already says "working".
private struct StatusLine: View {
    let row: AgentRow

    var body: some View {
        let message = row.message.flatMap { $0.isEmpty ? nil : $0 }
        let label = Theme.label(row.state, kind: row.kind)
        Group {
            switch (row.state, message) {
            case (.blocked, let message?):
                Text(label).foregroundStyle(Theme.amber) + Text("  ") + Text(message)
            case (.blocked, nil):
                Text(label).foregroundStyle(Theme.amber)
            case (.error, let message?):
                Text(label).foregroundStyle(Theme.red) + Text("  ") + Text(message)
            case (_, let message?):
                Text(message)
            case (_, nil):
                Text(label)
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .truncationMode(.tail)
    }
}

/// The shape of a state: spinning arc (or a filling ring when the program
/// reports progress), amber diamond, check, cross, ring.
struct StatusMark: View {
    let state: ProgramState
    var holding = true
    var progress: Int? = nil

    var body: some View {
        Group {
            switch state {
            case .working:
                if !holding {
                    ring
                } else if let progress {
                    ProgressRing(progress: progress)
                } else {
                    Spinner()
                }
            case .blocked:
                Image(systemName: "diamond.fill")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(holding ? AnyShapeStyle(Theme.amber) : AnyShapeStyle(.tertiary))
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(holding ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            case .error:
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(holding ? AnyShapeStyle(Theme.red) : AnyShapeStyle(.tertiary))
            case .idle:
                ring
            }
        }
        .frame(width: 12, height: 12)
    }

    private var ring: some View {
        Circle().strokeBorder(.tertiary, lineWidth: 1.2).frame(width: 8, height: 8)
    }
}

/// A determinate spinner: a faint track filled clockwise from the top.
private struct ProgressRing: View {
    let progress: Int

    var body: some View {
        ZStack {
            Circle().stroke(.tertiary, lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: CGFloat(progress) / 100)
                .stroke(.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 9, height: 9)
        .animation(.easeOut(duration: 0.3), value: progress)
        .help("\(progress)%")
    }
}

private struct Spinner: View {
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 9, height: 9)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

private struct RemoteMark: View {
    var body: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .help("You're away and remote control is on: holding longer so you can reply from your phone")
    }
}

/// Right-aligned time: elapsed while working, "zz 12m" while lingering
/// (time until it lets the Mac sleep), "∞" for open-ended holds.
private struct TimeTag: View {
    let row: AgentRow
    let now: Date

    var body: some View {
        Group {
            if row.isHoldingForWork {
                Text(Theme.duration(row.since, now))
            } else if let until = row.holdUntil {
                if until == .distantFuture {
                    Text("∞")
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "zzz").font(.system(size: 8, weight: .semibold))
                        Text(Theme.duration(now, until))
                    }
                    .help("Lets the Mac sleep at \(Theme.time(until))")
                }
            }
        }
        .font(.system(size: 11, weight: .regular))
        .monospacedDigit()
        .foregroundStyle(.tertiary)
    }
}

// MARK: Agent detail

/// One agent's details, shown in place of the list with a back link.
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
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 9.5, weight: .semibold))
                        Text("All agents")
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(alignment: .center, spacing: 9) {
                    StatusMark(state: row.state, holding: row.holdUntil != nil, progress: row.progress)
                    Text(row.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    if row.isRemote { RemoteMark() }
                    Spacer(minLength: 4)
                    TimeTag(row: row, now: now)
                }

                if let message = row.message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.9))
                        .lineLimit(8)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.wash))
                        .overlay(alignment: .leading) {
                            if row.state == .blocked {
                                Theme.amber.frame(width: 2).clipShape(Capsule()).padding(.vertical, 6)
                            }
                        }
                }

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
                    fact("State", "\(Theme.label(row.state, kind: row.kind)) for \(Theme.duration(row.since, now))")
                    if let progress = row.progress { fact("Progress", "\(progress)%") }
                    fact("Holding", holding(now))
                    fact("Remote", remote)
                    if let cwd = row.cwd { fact("Project", (cwd as NSString).abbreviatingWithTildeInPath) }
                    fact("Source", [row.origin.label, row.pid.map { "pid \($0)" }].compactMap { $0 }.joined(separator: " · "))
                }

                if !row.children.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Subagents").font(.system(size: 11)).foregroundStyle(.tertiary)
                        ForEach(row.children) { child in
                            HStack(spacing: 8) {
                                StatusMark(state: child.state, holding: child.holdUntil != nil, progress: child.progress)
                                Text(child.title).font(.system(size: 12)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(Theme.label(child.state, kind: nil) + (child.progress.map { " · \($0)%" } ?? ""))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                HStack(spacing: 14) {
                    if case .rex = row.origin {
                        LinkButton(title: "Show in Rex", symbol: "arrow.up.forward.app") {
                            Task { showOutcome = await controller.showInRex(row) }
                        }
                    }
                    if row.holdUntil != nil {
                        LinkButton(title: "Let it sleep", symbol: "moon.zzz") { controller.dismiss(row) }
                            .help("Stop this agent holding the Mac awake until its state changes")
                    }
                    LinkButton(title: copied ? "Copied" : "Copy", symbol: copied ? "checkmark" : "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(copyText(now), forType: .string)
                        copied = true
                    }
                    Spacer()
                }

                if showOutcome == .needsRemoteControl {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rex focused the pane, but switching sessions needs Remote Control turned on in Rex.")
                            .fixedSize(horizontal: false, vertical: true)
                        LinkButton(title: "Open Rex Settings", symbol: "gearshape") { RexMonitor.openRemoteControlSettings() }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                } else if showOutcome == .unavailable {
                    Text("Couldn't reach the Rex app.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func fact(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(key)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func holding(_ now: Date) -> String {
        if row.isDismissed { return "No, you let it sleep" }
        guard let until = row.holdUntil else { return "No (\(row.reason))" }
        if until == .distantFuture { return "Until you stop it" }
        if row.isHoldingForWork {
            let who = row.state == .working ? "" : "subagents are "
            return "While \(who)working, at most until \(Theme.time(until))"
        }
        return "Until \(Theme.time(until)), \(Theme.duration(now, until)) from now"
    }

    private var remote: String {
        guard row.remoteControlEnabled else { return "Remote control off" }
        if row.isRemote { return "You're away; holding longer for phone replies" }
        return "On; you're here, normal timeouts"
    }

    private func copyText(_ now: Date) -> String {
        var lines = ["\(row.name): \(Theme.label(row.state, kind: row.kind))"]
        if let message = row.message { lines.append(message) }
        lines.append("holding: \(holding(now))")
        lines.append("remote: \(remote)")
        if let cwd = row.cwd { lines.append("project: \(cwd)") }
        lines.append("source: \(row.origin.label)\(row.pid.map { " pid \($0)" } ?? "")")
        for child in row.children { lines.append("  \(child.title): \(child.state.rawValue)") }
        return lines.joined(separator: "\n")
    }
}

// MARK: Keep awake

/// Opened from the footer: pick a duration on a stepped slider and start.
private struct KeepAwakeDrawer: View {
    let controller: Controller
    let close: () -> Void
    @AppStorage("manualHoldStop") private var storedIndex = 3

    private var stops: [TimeInterval?] { ManualHold.stops(onAC: controller.onAC) }
    private var index: Int { min(max(storedIndex, 0), stops.count - 1) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let duration = stops[index]
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("Keep awake for")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(Theme.longDuration(duration))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                    Spacer()
                    Text(duration.map { "until \(Theme.time(context.date.addingTimeInterval($0)))" } ?? "until stopped")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                StepSlider(count: stops.count, index: Binding(get: { index }, set: { storedIndex = $0 }))
                HStack {
                    LinkButton(title: "Cancel", symbol: nil, action: close)
                    Spacer()
                    SolidButton(title: "Start") {
                        controller.holdManually(for: duration)
                        close()
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.wash))
        }
    }
}

/// A running manual hold: one slim line with a depleting rule underneath.
private struct ActiveHoldStrip: View {
    let controller: Controller

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            if let hold = controller.manualHold {
                let now = context.date
                let open = hold.until == .distantFuture
                let total = hold.until.timeIntervalSince(hold.since)
                let remaining = open || total <= 0 ? 1 : max(0, min(1, hold.until.timeIntervalSince(now) / total))
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "eye").font(.system(size: 10, weight: .semibold))
                        Text(open ? "Kept awake until you stop" : "Kept awake until \(Theme.time(hold.until))")
                            .font(.system(size: 12, weight: .medium))
                        if !open {
                            Text(Theme.duration(now, hold.until))
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if !open {
                            LinkButton(title: "+30m", symbol: nil) { controller.extendManualHold(by: 30 * 60) }
                        }
                        LinkButton(title: "Stop", symbol: nil) { controller.cancelManualHold() }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.wash)
                            Capsule().fill(.primary.opacity(0.7)).frame(width: geo.size.width * remaining)
                        }
                    }
                    .frame(height: 2)
                }
            }
        }
    }
}

/// A slider that snaps to evenly spaced stops: a hairline track with ticks
/// and a small white knob.
private struct StepSlider: View {
    let count: Int
    @Binding var index: Int

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 6
            let width = geo.size.width - inset * 2
            let step = count > 1 ? width / CGFloat(count - 1) : 0
            let x = inset + step * CGFloat(index)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 2).padding(.horizontal, inset)
                Capsule().fill(Color.white.opacity(0.75)).frame(width: max(0, x - inset), height: 2).offset(x: inset)
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(i <= index ? Color.white.opacity(0.75) : Color.white.opacity(0.22))
                        .frame(width: 1, height: 6)
                        .offset(x: inset + step * CGFloat(i) - 0.5)
                }
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .frame(width: 12, height: 12)
                    .offset(x: x - 6)
            }
            .frame(height: 16)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard step > 0 else { return }
                let raw = ((value.location.x - inset) / step).rounded()
                let next = Int(min(max(raw, 0), CGFloat(count - 1)))
                if next != index { index = next }
            })
        }
        .frame(height: 16)
        .accessibilityElement()
        .accessibilityLabel("Keep awake duration")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: index = min(index + 1, count - 1)
            case .decrement: index = max(index - 1, 0)
            @unknown default: break
            }
        }
    }
}

// MARK: Stay awake when closed

private struct LidRow: View {
    let controller: Controller
    @State private var installing = false

    /// How the status line should read: plain, good to go, or held back for safety.
    private enum Tone { case quiet, ready, caution }

    var body: some View {
        let (status, tone) = statusLine
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 11))
                .foregroundStyle(color(tone, fallback: .secondary))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text("Stay awake when closed")
                    .font(.system(size: 12))
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(color(tone, fallback: .tertiary))
            }
            Spacer()
            if controller.lidInstalled {
                Toggle("Stay awake when closed", isOn: Binding(
                    get: { controller.lidModeEnabled },
                    set: { controller.lidModeEnabled = $0 }))
                    .toggleStyle(InkSwitchStyle())
            } else {
                LinkButton(title: installing ? "Waiting…" : "Set up", symbol: nil) {
                    installing = true
                    Task {
                        await controller.installLidSupport()
                        installing = false
                    }
                }
                .disabled(installing)
            }
        }
        .help("With the lid closed and no display on, macOS sleeps right away. This keeps the Mac awake while agents need it, then lets it sleep. More in Settings.")
    }

    private var statusLine: (String, Tone) {
        guard controller.lidInstalled else { return ("One-time setup; asks for your password", .quiet) }
        switch controller.lidVerdict {
        case .armed:
            if !controller.lidClosed { return ("Close it anytime; agents keep running", .ready) }
            return controller.externalDisplay
                ? ("Closed; awake even if the display goes off", .ready)
                : ("Closed; awake for your agents", .ready)
        case .disarmed(.off):
            return ("Off; with no display on, the Mac sleeps", .quiet)
        case .disarmed(.nothingToHold):
            return ("Ready when an agent is working", .quiet)
        case .disarmed(.tooWarm):
            return ("Paused while the Mac is hot", .caution)
        case .disarmed(.lowBattery):
            return ("Paused: battery below \(LidPolicy.minimumBatteryPercent)%", .caution)
        case .disarmed(.batteryNotRemote):
            return ("On battery: only while you're away", .quiet)
        }
    }

    private func color(_ tone: Tone, fallback: HierarchicalShapeStyle) -> AnyShapeStyle {
        switch tone {
        case .quiet: AnyShapeStyle(fallback)
        case .ready: AnyShapeStyle(.primary)
        case .caution: AnyShapeStyle(Theme.amber)
        }
    }
}

// MARK: Controls

/// Quiet text button: secondary ink, brightening on hover.
private struct LinkButton: View {
    let title: String
    let symbol: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .medium)) }
                Text(title)
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The one filled button: white on dark.
private struct SolidButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(hovering ? 1 : 0.88)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A small switch drawn by the panel itself (system switches look inactive in
/// a panel that never activates the app).
private struct InkSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) { configuration.isOn.toggle() }
        } label: {
            Capsule()
                .fill(configuration.isOn ? Color.white.opacity(0.85) : Color.white.opacity(0.14))
                .frame(width: 26, height: 15)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? Color.black.opacity(0.85) : Color.white.opacity(0.7))
                        .padding(2.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stay awake when closed")
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

// MARK: Footer

private struct FooterView: View {
    let controller: Controller
    let navigation: PanelNavigation

    var body: some View {
        HStack(spacing: 2) {
            if controller.manualHold == nil {
                FooterButton(symbol: "eye", title: "Keep awake…", active: navigation.keepAwakeOpen) {
                    withAnimation(.snappy(duration: 0.22)) { navigation.keepAwakeOpen.toggle() }
                }
            }
            Spacer()
            FooterButton(symbol: "gearshape", title: nil, active: false) { navigation.openSettings() }
                .help("Settings, and how agry works")
            Menu {
                Button("Open Event Log") { NSWorkspace.shared.open(controller.debugDirectory.appending(path: "events.log")) }
                Button("Copy State") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(controller.stateDescription(), forType: .string)
                }
                Divider()
                if controller.updater.isAvailable {
                    Button("Check for Updates…") { controller.updater.checkForUpdates() }
                }
                Button("agry \(Updater.versionDescription)") {}.disabled(true)
                Divider()
                Button("Quit agry") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
        }
    }
}

private struct FooterButton: View {
    let symbol: String
    let title: String?
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11.5, weight: .medium))
                if let title { Text(title).font(.system(size: 11.5)) }
            }
            .foregroundStyle(active || hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(active ? Theme.washHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
