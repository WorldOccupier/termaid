import AppKit

/// While the Library is open, Termaid behaves like a regular app: Dock icon, ⌘-Tab entry and a main menu.
/// When the Library closes, it goes back to being a menu-bar-only accessory.
@MainActor final class LibraryAppMode: NSObject, NSWindowDelegate {
    private let app: NSApplication
    private lazy var mainMenu = Self.makeMainMenu()

    init(app: NSApplication) {
        self.app = app
    }

    func enter() {
        guard app.activationPolicy() != .regular else { return }
        app.setActivationPolicy(.regular)
        app.mainMenu = mainMenu
    }

    func windowWillClose(_ notification: Notification) {
        app.setActivationPolicy(.accessory)
    }

    private static func makeMainMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu("Termaid", [
            NSMenuItem(title: "Hide Termaid", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            .separator(),
            NSMenuItem(title: "Quit Termaid", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]))
        menu.addItem(submenu("File", [
            NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
        ]))
        menu.addItem(submenu("Edit", [
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ]))
        let window = submenu("Window", [
            NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
            NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""),
        ])
        menu.addItem(window)
        NSApplication.shared.windowsMenu = window.submenu
        return menu
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        items.forEach(sub.addItem)
        item.submenu = sub
        return item
    }
}
