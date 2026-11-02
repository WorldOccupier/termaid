import Foundation
import Testing
@testable import TermaidApp

@MainActor @Suite struct DiagramLibraryTests {
    private let fileURL = temporaryLibraryURL()

    @Test func changesSurviveRelaunch() {
        let library = DiagramLibrary(fileURL: fileURL)
        let kept = library.add(title: "Deploy", description: "d", mermaid: "flowchart LR", svg: "<svg/>")
        let removed = library.add(title: "Old", description: "", mermaid: "", svg: "")
        library.rename(kept.id, to: "  Release  ")
        library.remove(removed.id)

        let reopened = DiagramLibrary(fileURL: fileURL)
        #expect(reopened.items.map(\.title) == ["Release"])
        #expect(reopened.items.first?.id == kept.id)
    }

    @Test func blankRenameIsIgnored() {
        let library = DiagramLibrary(fileURL: fileURL)
        let item = library.add(title: "Deploy", description: "", mermaid: "", svg: "")
        library.rename(item.id, to: "   ")
        #expect(library.items.first?.title == "Deploy")
    }

    @Test func unreadableFileIsMovedAside() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        #expect(DiagramLibrary(fileURL: fileURL).items.isEmpty)
        let backup = fileURL.deletingLastPathComponent().appendingPathComponent("library.corrupt.json")
        #expect(try String(contentsOf: backup, encoding: .utf8) == "not json")
    }
}
