import AgryCore
import SwiftUI

/// The ⓘ pop-out: a legend for the glyph, state colors, badges and lid modes.
/// Timeouts come from the live config and the current power source.
struct HelpView: View {
    let config: PolicyConfig
    let onAC: Bool

    private var timeouts: Timeouts { config.timeouts(onAC: onAC) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("How agry works").font(.system(size: 14, weight: .semibold))
                Text("Keeps your Mac awake while agents work, and a little after, so results and questions wait for you.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HelpSection(title: "The eye") {
                GlyphLine(mood: .awake, title: "Awake", detail: "Something is holding the Mac awake.")
                GlyphLine(mood: .attention, title: "Watching you", detail: "An agent is blocked and needs you.")
                GlyphLine(mood: .resting, title: "Resting", detail: "Nothing holding. Sleep works as usual.")
            }

            HelpSection(title: "States · \(onAC ? "on AC" : "on battery")") {
                StateLine(state: .working, title: "Working", detail: "Holds while running (up to \(format(timeouts.workingCap))).")
                StateLine(state: .blocked, title: "Needs you", detail: "Waiting on permission or an answer. Holds \(format(timeouts.blocked)).")
                StateLine(state: .done, title: "Done", detail: "Finished, unread. Holds \(format(timeouts.finished)).")
                StateLine(state: .error, title: "Error", detail: "Failed and stopped. Holds \(format(timeouts.finished)).")
                StateLine(state: .idle, title: "Idle", detail: "At rest. Doesn't hold.")
            }

            HelpSection(title: "Badges") {
                BadgeLine(badge: Text("live"), detail: "Holding for as long as the agent works.")
                BadgeLine(badge: Text("12m"), detail: "Time left before this agent lets go.")
                BadgeLine(badge: Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Theme.accent),
                          detail: "Away mode: remote control is on and you haven't touched the Mac since it "
                            + "finished, so it holds at least \(format(timeouts.remote)) for replies from your phone. "
                            + "Touching the Mac cancels it.")
            }

            HelpSection(title: "Lid closed") {
                LidLine(title: "Armed", detail: "Safe to close the lid. The Mac stays awake.")
                LidLine(title: "Standing by", detail: "Not armed right now: nothing to hold, too warm, low battery, "
                    + "or on battery without remote work.")
            }

            Text("Timeouts live in config.json: settings menu → Edit Config…")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 300)
        .tint(Theme.accent)
    }

    private func format(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        guard minutes >= 60 else { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h\(String(format: "%02d", minutes % 60))"
    }
}

private struct HelpSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: title)
            content
        }
    }
}

/// A legend line: a fixed-width leading mark, a title and one line of detail.
private struct LegendLine<Mark: View>: View {
    let title: String?
    let detail: String
    @ViewBuilder let mark: Mark

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            mark.frame(width: 26, alignment: .center)
            (title.map { Text("\($0)  ").font(.system(size: 11.5, weight: .medium)) } ?? Text(""))
                + Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
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
                .foregroundStyle(mood == .resting ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.accent))
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
            StateDot(state: state, active: state != .idle)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        }
    }
}

private struct BadgeLine<Badge: View>: View {
    let badge: Badge
    let detail: String

    var body: some View {
        LegendLine(title: nil, detail: detail) {
            badge.font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}

private struct LidLine: View {
    let title: String
    let detail: String

    var body: some View {
        LegendLine(title: title, detail: detail) {
            Image(systemName: "laptopcomputer").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
