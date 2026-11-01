import AppKit

/// The menu-bar logo icon. It turns red while listening and holds the app's menu.
@MainActor
final class MenuBar: NSObject {
    private let statusItem: NSStatusItem
    private let onTalk: @MainActor () -> Void
    private let onType: @MainActor () -> Void
    private let onLibrary: @MainActor () -> Void
    private let onSetup: @MainActor () -> Void

    var button: NSStatusBarButton? { statusItem.button }

    init(onTalk: @escaping @MainActor () -> Void,
         onType: @escaping @MainActor () -> Void,
         onLibrary: @escaping @MainActor () -> Void,
         onSetup: @escaping @MainActor () -> Void) {
        self.onTalk = onTalk
        self.onType = onType
        self.onLibrary = onLibrary
        self.onSetup = onSetup
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = MenuBarIcon.make()
            button.wantsLayer = true
            button.layer?.cornerRadius = 6
        }

        let menu = NSMenu()
        menu.addItem(item("Talk (hold ⌥ Space)", #selector(talk)))
        menu.addItem(item("Type… (⌥ T)", #selector(typeText)))
        menu.addItem(item("Library", #selector(showLibrary)))
        menu.addItem(.separator())
        menu.addItem(item("Setup…", #selector(showSetup)))
        menu.addItem(item("Quit termaid", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    func setListening(_ listening: Bool) {
        guard let button = statusItem.button else { return }
        button.layer?.backgroundColor = listening ? NSColor.systemRed.withAlphaComponent(0.85).cgColor : nil
        button.contentTintColor = listening ? .white : nil
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    @objc private func talk() { onTalk() }
    @objc private func typeText() { onType() }
    @objc private func showLibrary() { onLibrary() }
    @objc private func showSetup() { onSetup() }
    @objc private func quit() { NSApp.terminate(nil) }
}
