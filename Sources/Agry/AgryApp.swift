import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = Controller()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also right when launched as a bare executable (no LSUIElement).
        NSApp.setActivationPolicy(.accessory)
        controller.start()
        let statusItem = StatusItemController(controller: controller)
        self.statusItem = statusItem
        if ProcessInfo.processInfo.environment["AGRY_DEBUG_PANEL_CYCLE"] != nil {
            debugPanelCycle(statusItem, controller: controller)
        }
        if let minutes = ProcessInfo.processInfo.environment["AGRY_SNAPSHOT_HOLD"].flatMap(Double.init) {
            controller.holdManually(for: minutes * 60)
        }
        if let path = ProcessInfo.processInfo.environment["AGRY_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [controller] in
                MainActor.assumeIsolated { renderSnapshot(controller: controller, to: URL(fileURLWithPath: path)) }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}

@main
struct AgryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // The menu bar item and panel are AppKit (see StatusItemController); the
    // app needs a scene, so it declares an empty Settings one.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

extension Controller {
    var mood: EyeGlyph.Mood {
        guard decision.isHolding else { return .resting }
        return rows.contains { $0.state == .blocked && $0.holdUntil != nil } ? .attention : .awake
    }
}

/// Dev aid: renders the live panel (light and dark) to PNGs without opening it.
@MainActor
private func renderSnapshot(controller: Controller, to url: URL) {
    for scheme in [ColorScheme.light, .dark] {
        let navigation = PanelNavigation()
        navigation.keepAwakeOpen = ProcessInfo.processInfo.environment["AGRY_SNAPSHOT_DRAWER"] != nil
        navigation.selected = ProcessInfo.processInfo.environment["AGRY_SNAPSHOT_EXPAND"]
            .flatMap { prefix in controller.rows.first { $0.name.hasPrefix(prefix) }?.id }
        let view = PanelView(controller: controller, navigation: navigation, allowsScrolling: false)
            .background(Color(white: 0.11))
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { continue }
        let target = url.deletingPathExtension().appendingPathExtension("\(scheme == .dark ? "dark" : "light").png")
        try? png.write(to: target)
    }
    for scheme in [ColorScheme.light, .dark] {
        let help = HelpView(config: controller.config, onAC: controller.onAC)
            .background(Color(white: 0.11))
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: help)
        renderer.scale = 2
        if let tiff = renderer.nsImage?.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url.deletingPathExtension().appendingPathExtension("help.\(scheme == .dark ? "dark" : "light").png"))
        }
    }
    let glyphs = HStack(spacing: 24) {
        ForEach([EyeGlyph.Mood.awake, .attention, .resting], id: \.self) { mood in
            VStack(spacing: 10) {
                EyeGlyphView(mood: mood).frame(width: 80)
                Image(nsImage: EyeGlyph.menuBarImage(mood))
            }
        }
    }
    .padding(20)
    .background(Color.white)
    .foregroundStyle(.black)
    let renderer = ImageRenderer(content: glyphs)
    renderer.scale = 2
    if let tiff = renderer.nsImage?.tiffRepresentation,
       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
        try? png.write(to: url.deletingPathExtension().appendingPathExtension("glyphs.png"))
    }
    controller.note("snapshot written next to \(url.path)")
}

/// Dev aid: opens the panel, drills into the first agent and back, logging the
/// panel frame at each step so resizing can be checked without clicking.
@MainActor
private func debugPanelCycle(_ statusItem: StatusItemController, controller: Controller) {
    let steps: [(TimeInterval, String, () -> Void)] = [
        (3, "open", { statusItem.openPanel() }),
        (5, "detail", { statusItem.navigation.selected = controller.rows.first?.id }),
        (7, "back", { statusItem.navigation.selected = nil }),
        (9, "close", { statusItem.closePanel() }),
        (10, "reopen", { statusItem.openPanel() }),
    ]
    for (delay, name, action) in steps {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                action()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    MainActor.assumeIsolated {
                        controller.note("panel \(name): \(statusItem.panelFrame) open=\(statusItem.isOpen)")
                    }
                }
            }
        }
    }
}
