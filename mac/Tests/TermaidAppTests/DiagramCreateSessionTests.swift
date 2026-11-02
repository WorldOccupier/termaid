import Foundation
import Testing
@testable import TermaidApp

@MainActor @Suite struct DiagramCreateSessionTests {
    private let creator = ScriptedDiagramCreator()
    private let library = DiagramLibrary(fileURL: temporaryLibraryURL())

    private func makeSession() -> DiagramCreateSession {
        DiagramCreateSession(creator: creator, voice: UnusedVoiceInput(), library: library)
    }

    private func describe(_ description: String, in session: DiagramCreateSession) async {
        session.instruction = description
        session.applyInstruction()
        while session.activity != .idle { await Task.yield() }
    }

    @Test func typedDescriptionIsDrawnAndSaved() async {
        let session = makeSession()
        await describe("build the app. ship it", in: session)

        let saved = library.items.first
        #expect(session.createdItem?.id == saved?.id)
        #expect(saved?.title == "Build the app")
        #expect(saved?.description == "build the app. ship it")
        #expect(saved?.mermaid == "flowchart LR\nbuild the app\nship it")
        #expect(session.currentStep == 1)
        #expect(!session.canApply)
    }

    @Test func failedDescriptionGoesBackIntoTheField() async {
        let session = makeSession()
        creator.shouldFail = true
        await describe("build the app", in: session)

        #expect(session.errorMessage == "model failed")
        #expect(session.instruction == "build the app")
        #expect(!session.isDrawing)
        #expect(library.items.isEmpty)
    }

    @Test func cancellingMidDrawingSavesNothing() async {
        let session = makeSession()
        creator.holding = true
        session.instruction = "build the app"
        session.applyInstruction()
        while !session.isDrawing { await Task.yield() }

        session.cancel()
        creator.release()
        while !creator.finished { await Task.yield() }
        await Task.yield()

        #expect(!session.isDrawing)
        #expect(session.createdItem == nil)
        #expect(library.items.isEmpty)
    }
}
