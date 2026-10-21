import AgryCore
import SwiftUI

/// The help pop-out: a legend for the eye, the state marks and the time tags.
/// Timeouts come from the live config and the current power source.
struct HelpView: View {
    let config: PolicyConfig
    let onAC: Bool
    var systemNeverSleeps = false

    private var timeouts: Timeouts { config.timeouts(onAC: onAC) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How agry works").font(.system(size: 14, weight: .semibold))
                Text("macOS sleeps a Mac nobody is using. agry holds that off while agents work, and a little after, so results and questions are there when you're back.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HelpSection(title: "The eye") {
                GlyphLine(mood: .awake, title: "Awake", detail: "Something is keeping the Mac awake.")
                GlyphLine(mood: .attention, title: "Needs you", detail: "An agent is blocked, waiting on you.")
                GlyphLine(mood: .resting, title: "Resting", detail: "Nothing holding. The Mac sleeps as usual.")
            }

            HelpSection(title: "Agents (\(onAC ? "on AC" : "on battery"))") {
                StateLine(state: .working, title: "Working", detail: "Holds while running, up to \(format(timeouts.workingCap)).")
                StateLine(state: .blocked, title: "Needs you", detail: "Waiting on permission or an answer. Holds \(format(timeouts.blocked)).")
                StateLine(state: .done, title: "Done", detail: "Finished. Holds \(format(timeouts.finished)) so you can catch up.")
                StateLine(state: .error, title: "Error", detail: "Failed and stopped. Holds \(format(timeouts.finished)).")
                StateLine(state: .idle, title: "Idle", detail: "At rest. Doesn't hold.")
            }

            HelpSection(title: "Times") {
                MarkLine(mark: Text("12m").monospacedDigit(), detail: "How long it has been working.")
                MarkLine(mark: HStack(spacing: 3) { Image(systemName: "zzz").font(.system(size: 8, weight: .semibold)); Text("4m") },
                         detail: "Until agry stops holding.")
                MarkLine(mark: Image(systemName: "dot.radiowaves.left.and.right"),
                         detail: "You're away and remote control is on, so it holds at least \(format(timeouts.remote)) "
                            + "for replies from your phone. Touching the Mac cancels that.")
            }

            HelpSection(title: "Stay awake when closed") {
                Paragraph("With the lid closed and no display on, macOS sleeps right away, mid-task or not. "
                    + "That covers closing the lid, and turning off or unplugging an external display while the lid is shut.")
                Paragraph("With this on, agry keeps the Mac awake through that, but only while:")
                RuleLine(symbol: "eye", text: "Something is holding.")
                RuleLine(symbol: "thermometer.medium", text: "The Mac isn't running hot.")
                RuleLine(symbol: "powerplug.portrait",
                         text: "It's plugged in, or above \(LidPolicy.minimumBatteryPercent)% on battery while you're away with remote control.")
                Paragraph("When that ends, agry puts the Mac to sleep. A display that's only asleep or on another input still counts as on.")
                Note("Setup adds one admin rule that allows only `pmset disablesleep`. Remove it in Settings.")
            }

            if systemNeverSleeps {
                HelpSection(title: "Your Mac") {
                    Paragraph("macOS is set never to sleep on \(onAC ? "power adapter" : "battery") by itself, so an idle Mac stays awake "
                        + "whatever agry does. To let it sleep when agents are done, turn off "
                        + "\"Prevent automatic sleeping\" in System Settings › Battery › Options.")
                }
            }

            Note("Change these times in Settings (… menu).")
        }
        .padding(16)
        .frame(width: 300)
        .environment(\.colorScheme, .dark)
    }

    private func format(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        guard minutes >= 60 else { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h\(String(format: "%02d", minutes % 60))"
    }
}

private struct Paragraph: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct HelpSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
            content
        }
    }
}

/// A legend line: a fixed-width leading mark, a title and its explanation.
private struct LegendLine<Mark: View>: View {
    let title: String?
    let detail: String
    @ViewBuilder let mark: Mark

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            mark.fixedSize().frame(width: 34, alignment: .center)
            (title.map { Text("\($0)  ").font(.system(size: 12, weight: .medium)) } ?? Text(""))
                + Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GlyphLine: View {
    let mood: EyeGlyph.Mood
    let title: String
    let detail: String

    var body: some View {
        LegendLine(title: title, detail: detail) {
            EyeGlyphView(mood: mood, lineWidth: 1.5)
                .frame(width: 20)
                .foregroundStyle(mood == .resting ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        }
    }
}

private struct StateLine: View {
    let state: ProgramState
    let title: String
    let detail: String

    var body: some View {
        LegendLine(title: title, detail: detail) {
            StatusMark(state: state)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        }
    }
}

private struct RuleLine: View {
    let symbol: String
    let text: String

    var body: some View {
        LegendLine(title: nil, detail: text) {
            Image(systemName: symbol).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }
}

private struct MarkLine<Mark: View>: View {
    let mark: Mark
    let detail: String

    var body: some View {
        LegendLine(title: nil, detail: detail) {
            mark.font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }
}
