import AppKit

/// While the Library is open, Termaid behaves like a regular app: Dock icon, ⌘-Tab entry and a visible
/// main menu (see MainMenu). When the Library closes, it goes back to being a menu-bar-only accessory.
@MainActor final class LibraryAppMode: NSObject, NSWindowDelegate {
    private let app: NSApplication

    init(app: NSApplication) {
        self.app = app
    }

    func enter() {
        guard app.activationPolicy() != .regular else { return }
        app.setActivationPolicy(.regular)
    }

    func windowWillClose(_ notification: Notification) {
        app.setActivationPolicy(.accessory)
    }
}
