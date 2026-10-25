import AppKit
import SwiftUI

/// A plain titled window, used for Settings. agry is a menu bar accessory,
/// so it activates itself to bring the window forward. The window is let go
/// when it closes: SwiftUI keeps a hidden window's views live, animations and
/// all, and agry runs for days.
@MainActor
final class AppWindow {
    private let title: String
    private let makeContent: () -> AnyView
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

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
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.release() }
            }
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func release() {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        window = nil
    }
}
