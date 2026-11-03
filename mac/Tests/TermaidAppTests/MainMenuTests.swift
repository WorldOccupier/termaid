import AppKit
import Testing
@testable import TermaidApp

@MainActor @Suite struct MainMenuTests {
    /// Text fields only get these shortcuts if a main-menu item carries them.
    @Test func editMenuHandlesTextShortcuts() throws {
        let edit = try #require(MainMenu(newDiagram: {}).menu.item(withTitle: "Edit")?.submenu)
        let shortcuts = Dictionary(uniqueKeysWithValues: edit.items.compactMap { item in
            item.action.map { (NSStringFromSelector($0), item.keyEquivalent) }
        })
        #expect(shortcuts == ["undo:": "z", "redo:": "z", "cut:": "x", "copy:": "c", "paste:": "v", "selectAll:": "a"])
    }
}
