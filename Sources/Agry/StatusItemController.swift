import AppKit
import Observation
import SwiftUI

/// Which page the panel shows. Owned outside the view so the panel can reset
/// to the list when it closes, and so dev hooks can drive it.
@MainActor
@Observable
final class PanelNavigation {
    var selected: String?
    var keepAwakeOpen = false
    @ObservationIgnored var openSettings: () -> Void = {}
}

/// The menu bar icon and its panel.
///
/// Replaces SwiftUI's MenuBarExtra, whose window grows with its content but
/// does not shrink back, leaving transparent bands. Here the panel is resized
/// to the content's fitting size on every layout change, top edge pinned under
/// the icon.
@MainActor
final class StatusItemController: NSObject {
    private let controller: Controller
    let navigation = PanelNavigation()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: AgryPanel
    private let hosting: SizeReportingHostingView<AnyView>
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?
    private let settings: AppWindow

    init(controller: Controller) {
        self.controller = controller
        hosting = SizeReportingHostingView(rootView: AnyView(EmptyView()))
        panel = AgryPanel(contentRect: NSRect(x: 0, y: 0, width: Theme.width, height: 400))
        settings = AppWindow(title: "agry Settings") { SettingsView(controller: controller) }
        super.init()
        navigation.openSettings = { [weak self, controller] in
            self?.closePanel()
            controller.reloadConfig()
            self?.settings.show()
        }

        hosting.rootView = AnyView(PanelView(controller: controller, navigation: navigation))
        hosting.onFittingSizeChange = { [weak self] in self?.fitPanel() }

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
        ])
        panel.contentView = background
        // The panel is always dark ("nocturnal"), whatever the system appearance.
        panel.appearance = NSAppearance(named: .darkAqua)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
        }
        trackIcon()
    }

    // MARK: Icon

    /// Redraws the icon whenever the mood changes.
    private func trackIcon() {
        let mood = withObservationTracking {
            controller.mood
        } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.trackIcon() } }
        }
        statusItem.button?.image = EyeGlyph.menuBarImage(mood)
        statusItem.button?.setAccessibilityLabel(mood == .resting ? "agry: sleep allowed" : "agry: keeping awake")
    }

    // MARK: Panel

    var isOpen: Bool { panel.isVisible }

    @objc func togglePanel() {
        controller.note("panel: icon clicked, \(isOpen ? "closing" : "opening")")
        controller.flushDebugLog()
        isOpen ? closePanel() : openPanel()
    }

    func openPanel() {
        controller.evaluate()
        fitPanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        statusItem.button?.highlight(true)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                // The status item is drawn by another process on recent macOS,
                // so a click on it arrives here too. Leave that click to the
                // button's own toggle, or the panel closes and instantly reopens.
                guard let self else { return }
                let point = NSEvent.mouseLocation
                let onIcon = self.iconFrameContains(point)
                self.controller.note("panel: outside click at \(point) icon=\(self.iconFrame.map { "\($0)" } ?? "-") \(onIcon ? "ignored (icon)" : "closing")")
                self.controller.flushDebugLog()
                if !onIcon { self.closePanel() }
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // Esc
            MainActor.assumeIsolated { self?.closePanel() }
            return nil
        }
    }

    func closePanel() {
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        navigation.selected = nil
        navigation.keepAwakeOpen = false
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        outsideClickMonitor = nil
        keyMonitor = nil
    }

    private var iconFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func iconFrameContains(_ point: NSPoint) -> Bool {
        iconFrame?.insetBy(dx: -2, dy: -2).contains(point) ?? false
    }

    /// Sizes the panel to its content and pins its top edge under the icon.
    func fitPanel() {
        let size = hosting.fittingSize
        guard size.height > 0, let button = statusItem.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var x = anchor.minX
        x = min(x, screen.maxX - size.width - 8)
        x = max(x, screen.minX + 8)
        let top = anchor.minY - 6
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    var panelFrame: NSRect { panel.frame }
}

/// A borderless, non-activating panel that can still take key focus for
/// buttons, text selection and Esc.
final class AgryPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }
}

/// Reports when SwiftUI's fitting size may have changed.
final class SizeReportingHostingView<Content: View>: NSHostingView<Content> {
    var onFittingSizeChange: (() -> Void)?
    private var lastSize = NSSize.zero

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        reportIfChanged()
    }

    override func layout() {
        super.layout()
        reportIfChanged()
    }

    private func reportIfChanged() {
        let size = fittingSize
        guard size != lastSize else { return }
        lastSize = size
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onFittingSizeChange?() }
        }
    }
}
