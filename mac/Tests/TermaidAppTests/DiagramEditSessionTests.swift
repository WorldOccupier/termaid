import Foundation
import Testing
@testable import TermaidApp

@MainActor @Suite struct DiagramEditSessionTests {
    private let editor = ScriptedDiagramEditor()
    private let library = DiagramLibrary(fileURL: temporaryLibraryURL())

    private func makeSession() -> DiagramEditSession {
        let item = library.add(title: "Deploy", description: "build then ship", mermaid: "flowchart LR", svg: "<svg/>")
        return DiagramEditSession(item: item, editor: editor, voice: UnusedVoiceInput(), library: library)
    }

    private func apply(_ instruction: String, in session: DiagramEditSession) async {
        session.instruction = instruction
        session.applyInstruction()
        while session.activity != .idle { await Task.yield() }
    }

    @Test func savedDiagramHoldsEveryAppliedChange() async {
        let session = makeSession()
        await apply("add test", in: session)
        await apply("add lint", in: session)
        session.save()

        let saved = library.items.first
        #expect(saved?.mermaid == "flowchart LR\nadd test\nadd lint")
        #expect(saved?.description == "build then ship add test add lint")
    }

    @Test func undoRestoresThePreviousDraft() async {
        let session = makeSession()
        await apply("add test", in: session)
        session.undo()

        #expect(session.previewSVG == "<svg/>")
        #expect(!session.canSave)
    }

    @Test func failedEditKeepsTheDraftAndShowsTheError() async {
        let session = makeSession()
        editor.shouldFail = true
        await apply("add test", in: session)

        #expect(session.errorMessage == "model failed")
        #expect(session.appliedChanges.isEmpty)
        #expect(session.previewSVG == "<svg/>")
    }
}
