import AppKit

/// The app's main menu. AppKit routes key equivalents such as ⌘V through it, so text fields only get
/// paste, cut and undo from these Edit items. It is installed at launch, not with the Library, because the
/// capsule and setup fields need it too; in menu-bar-only mode the menu is hidden but still handles keys.
@MainActor final class MainMenu: NSObject {
    private let newDiagram: @MainActor () -> Void
    private(set) lazy var menu = makeMenu()

    init(newDiagram: @escaping @MainActor () -> Void) {
        self.newDiagram = newDiagram
    }

    @objc private func startNewDiagram() { newDiagram() }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(Self.submenu("Termaid", [
            NSMenuItem(title: "Hide Termaid", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            .separator(),
            NSMenuItem(title: "Quit Termaid", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]))
        let newItem = NSMenuItem(title: "New Diagram", action: #selector(startNewDiagram), keyEquivalent: "n")
        newItem.target = self
        menu.addItem(Self.submenu("File", [
            newItem,
            .separator(),
            NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
        ]))
        menu.addItem(Self.submenu("Edit", Self.editItems()))
        let window = Self.submenu("Window", [
            NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
            NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""),
        ])
        menu.addItem(window)
        NSApplication.shared.windowsMenu = window.submenu
        return menu
    }

    private static func editItems() -> [NSMenuItem] {
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        return [
            NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"),
            redo,
            .separator(),
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ]
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        items.forEach(sub.addItem)
        item.submenu = sub
        return item
    }
}
