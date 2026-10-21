import AppKit
import SwiftUI

/// A plain titled window, used for Settings. agry is a menu bar accessory,
/// so it activates itself to bring the window forward, and keeps one window
/// for the app's lifetime.
@MainActor
final class AppWindow {
    private let title: String
    private let makeContent: () -> AnyView
    private var window: NSWindow?

    init(title: String, @ViewBuilder content: @escaping () -> some View) {
        self.title = title
        makeContent = { AnyView(content()) }
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: makeContent()))
            window.title = title
            window.styleMask = [.titled, .closable]
            window.appearance = NSAppearance(named: .darkAqua)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
