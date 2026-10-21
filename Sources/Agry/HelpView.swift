import AgryCore
import SwiftUI

/// The help window: what the eye and the marks mean, how long each state
/// holds on either power source, and how staying awake when closed works.
/// Times come from the live config.
struct HelpView: View {
    let controller: Controller

    private var config: PolicyConfig { controller.config }

    var body: some View {
        // Taller than a laptop screen, so it scrolls within a fixed window.
        ScrollView {
            content
        }
        .frame(width: 580, height: 720)
        .environment(\.colorScheme, .dark)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .top, spacing: 16) {
                EyeGlyphView(mood: .awake, lineWidth: 2).frame(width: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text("How agry works").font(.system(size: 18, weight: .semibold))
                    Paragraph("macOS sleeps a Mac nobody is using. agry holds that off while your agents work, "
                        + "and for a while after, so results and questions are waiting when you're back.")
                }
            }

            if controller.systemNeverSleeps {
                Callout(
                    title: "macOS is set never to sleep on \(controller.onAC ? "power adapter" : "battery")",
                    text: "So an idle Mac stays awake whatever agry does. To let it sleep when agents are done, "
                        + "turn off \"Prevent automatic sleeping\" in System Settings › Battery › Options.")
            }

            HelpSection("The menu bar eye") {
                HStack(alignment: .top, spacing: 12) {
                    EyeCard(mood: .awake, title: "Awake", detail: "Something is keeping the Mac awake.")
                    EyeCard(mood: .attention, title: "Needs you", detail: "An agent is waiting on you.")
                    EyeCard(mood: .resting, title: "Resting", detail: "Nothing holding; the Mac sleeps as usual.")
                }
            }

            HelpSection("How long each state holds") {
                HoldTable(config: config, onAC: controller.onAC)
                Footnote("Touching the Mac ends the remote-control hold. Change any of these times in Settings.")
            }

            HelpSection("Times in the list") {
                HStack(alignment: .firstTextBaseline, spacing: 28) {
                    MarkLine(detail: "How long it has been working") { Text("12m").monospacedDigit() }
                    MarkLine(detail: "Until agry stops holding") {
                        HStack(spacing: 3) {
                            Image(systemName: "zzz").font(.system(size: 8, weight: .semibold))
                            Text("4m").monospacedDigit()
                        }
                    }
                }
            }

            HelpSection("Stay awake when closed") {
                Paragraph("With the lid closed and no display on, macOS sleeps right away, even mid-task. That includes "
                    + "turning off or unplugging your monitor while the lid is shut. A monitor that's only asleep or "
                    + "on another input still counts as on.")
                Paragraph("With this on, agry keeps the Mac awake through that while all of these are true:")
                VStack(alignment: .leading, spacing: 6) {
                    RuleLine(symbol: "eye", text: "Something is holding.")
                    RuleLine(symbol: "thermometer.medium", text: "The Mac isn't running hot.")
                    RuleLine(symbol: "powerplug.portrait",
                             text: "It's plugged in, or above \(LidPolicy.minimumBatteryPercent)% on battery while you're away with remote control.")
                }
                .padding(.leading, 2)
                Paragraph("When they stop being true, agry puts the Mac to sleep.")
                Footnote("Setup adds one admin rule that allows only `pmset disablesleep`. You can remove it in Settings.")
            }
        }
        .padding(28)
    }
}

/// States down the side, power sources across. The current source is brighter.
private struct HoldTable: View {
    let config: PolicyConfig
    let onAC: Bool

    private static let timeWidth: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Spacer()
                header("Plugged in", current: onAC)
                header("On battery", current: !onAC)
            }
            .padding(.bottom, 6)
            row(StatusMark(state: .working), "Working", "Running. Capped in case one gets stuck.", \.workingCap, prefix: "up to ")
            row(StatusMark(state: .blocked), "Needs you", "Waiting on permission or an answer.", \.blocked)
            row(StatusMark(state: .done), "Done", "Finished, so you can catch up.", \.finished)
            row(StatusMark(state: .error), "Error", "Failed and stopped.", \.finished)
            row(StatusMark(state: .idle), "Idle", "At rest.", nil)
            row(Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 10)).foregroundStyle(.secondary),
                "Remote control", "You're away with remote control on, so replies from your phone can land.",
                \.remote, prefix: "at least ")
        }
    }

    private func header(_ title: String, current: Bool) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(current ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            .frame(width: Self.timeWidth, alignment: .trailing)
    }

    private func row(_ mark: some View, _ title: String, _ detail: String,
                     _ path: KeyPath<Timeouts, TimeInterval>?, prefix: String = "") -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            mark.frame(width: 28, alignment: .leading)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            time(path.map { config.ac[keyPath: $0] }, prefix: prefix, current: onAC)
            time(path.map { config.battery[keyPath: $0] }, prefix: prefix, current: !onAC)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Theme.hairline.frame(height: 1) }
    }

    private func time(_ seconds: TimeInterval?, prefix: String, current: Bool) -> some View {
        Group {
            if let seconds {
                Text(prefix).foregroundStyle(.tertiary) + Text(Theme.longDuration(seconds))
            } else {
                Text("no hold").foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(current ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .frame(width: Self.timeWidth, alignment: .trailing)
    }
}

private struct EyeCard: View {
    let mood: EyeGlyph.Mood
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyeGlyphView(mood: mood, lineWidth: 1.5)
                .frame(width: 26, height: 18)
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

private struct Callout: View {
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.amber.opacity(0.35)))
    }
}

private struct HelpSection<Content: View>: View {
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
