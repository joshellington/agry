import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = Controller()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also right when launched as a bare executable (no LSUIElement).
        NSApp.setActivationPolicy(.accessory)
        controller.start()
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

    var body: some Scene {
        MenuBarExtra {
            PanelView(controller: delegate.controller)
        } label: {
            MenuBarLabel(controller: delegate.controller)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    let controller: Controller

    var body: some View {
        let mood = controller.mood
        Image(nsImage: EyeGlyph.menuBarImage(mood))
            .accessibilityLabel(mood == .resting ? "agry: sleep allowed" : "agry: keeping awake")
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
        let view = PanelView(controller: controller)
            .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.96))
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { continue }
        let target = url.deletingPathExtension().appendingPathExtension("\(scheme == .dark ? "dark" : "light").png")
        try? png.write(to: target)
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
