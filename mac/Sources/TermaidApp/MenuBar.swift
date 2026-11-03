import AppKit

/// The menu-bar logo icon. It turns red while listening and holds the app's menu.
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let onTalk: @MainActor () -> Void
    private let onType: @MainActor () -> Void
    private let onLibrary: @MainActor () -> Void
    private let onSetup: @MainActor () -> Void
    private let setupHasWork: @MainActor () -> Bool
    private var setupItem: NSMenuItem?

    var button: NSStatusBarButton? { statusItem.button }

    init(onTalk: @escaping @MainActor () -> Void,
         onType: @escaping @MainActor () -> Void,
         onLibrary: @escaping @MainActor () -> Void,
         onSetup: @escaping @MainActor () -> Void,
         setupHasWork: @escaping @MainActor () -> Bool) {
        self.onTalk = onTalk
        self.onType = onType
        self.onLibrary = onLibrary
        self.onSetup = onSetup
        self.setupHasWork = setupHasWork
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
        let setup = item("Setup…", #selector(showSetup))
        setupItem = setup
        menu.addItem(setup)
        menu.addItem(item("Quit termaid", #selector(quit), key: "q"))
        menu.delegate = self
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
    /// Setup only shows when it has something to fix, so a fully set-up app has a shorter menu.
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated { setupItem?.isHidden = !setupHasWork() }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
