import AgryCore
import AppKit

/// The menu bar item. The menu is rebuilt each time it opens.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let controller: Controller
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    init(controller: Controller) {
        self.controller = controller
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        controller.onChange = { [weak self] in self?.refreshIcon() }
        refreshIcon()
    }

    private func refreshIcon() {
        let holding = controller.decision.isHolding
        let name = holding ? "cup.and.heat.waves.fill" : "cup.and.saucer"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: holding ? "Keeping awake" : "Not holding")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = holding ? "agry: \(controller.summary(of: controller.decision))" : "agry: not holding"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        controller.evaluate()
        menu.removeAllItems()
        let decision = controller.decision

        menu.addItem(info(decision.isHolding ? "Keeping awake" : "Sleep allowed", bold: true))
        let rex = controller.rex.isConnected ? "Rex connected" : "Rex not connected"
        menu.addItem(info("\(controller.power.onAC ? "On AC power" : "On battery") · \(rex)"))

        if !decision.verdicts.isEmpty {
            menu.addItem(.separator())
            for verdict in decision.verdicts { menu.addItem(info(describe(verdict))) }
        }

        menu.addItem(.separator())
        let away = action("Away Mode (Remote Timeouts)", #selector(toggleAway))
        away.state = controller.forceRemote ? .on : .off
        menu.addItem(away)
        menu.addItem(keepAwakeItem())

        menu.addItem(.separator())
        menu.addItem(debugItem())
        menu.addItem(action("Quit agry", #selector(quit), key: "q"))
    }

    // MARK: Items

    private func describe(_ verdict: RecordVerdict) -> String {
        let record = verdict.record
        var parts = [record.app ?? "program", verdict.reason]
        if let message = record.message, !message.isEmpty {
            parts.append(message.count > 48 ? String(message.prefix(47)) + "…" : message)
        }
        if let until = verdict.holdUntil {
            parts.append(until == .distantFuture ? "until off" : "until \(until.formatted(date: .omitted, time: .shortened))")
        }
        return (verdict.holdUntil != nil ? "● " : "○ ") + parts.joined(separator: " · ")
    }

    private func keepAwakeItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Keep Awake", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (title, minutes) in [("15 Minutes", 15), ("1 Hour", 60), ("3 Hours", 180)] {
            let entry = action(title, #selector(holdFor(_:)))
            entry.tag = minutes
            sub.addItem(entry)
        }
        let forever = action("Until Turned Off", #selector(holdFor(_:)))
        forever.tag = 0
        sub.addItem(forever)
        if controller.hasManualHold {
            sub.addItem(.separator())
            sub.addItem(action("Cancel Manual Hold", #selector(cancelHold)))
        }
        item.submenu = sub
        return item
    }

    private func debugItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.addItem(action("Open Event Log", #selector(openLog)))
        sub.addItem(action("Copy State", #selector(copyState)))
        sub.addItem(action("Re-evaluate", #selector(reevaluate)))
        item.submenu = sub
        return item
    }

    private func info(_ title: String, bold: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if bold {
            item.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 0).bold()])
        }
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: Actions

    @objc private func toggleAway() { controller.forceRemote.toggle() }

    @objc private func holdFor(_ sender: NSMenuItem) {
        controller.holdManually(for: sender.tag == 0 ? nil : TimeInterval(sender.tag * 60))
    }

    @objc private func cancelHold() { controller.cancelManualHold() }

    @objc private func reevaluate() { controller.evaluate() }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openLog() {
        NSWorkspace.shared.open(controller.debugDirectory.appending(path: "events.log"))
    }

    @objc private func copyState() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(controller.stateDescription(), forType: .string)
    }
}

private extension NSFont {
    func bold() -> NSFont { NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask) }
}
