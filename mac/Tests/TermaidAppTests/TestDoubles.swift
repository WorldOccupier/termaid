import Foundation
@testable import TermaidApp

/// Appends each instruction to the Mermaid, or throws when told to.
@MainActor final class ScriptedDiagramEditor: DiagramEditing {
    struct Failure: LocalizedError { var errorDescription: String? { "model failed" } }
    var shouldFail = false

    func edit(_ mermaid: String, instruction: String,
              onStep: @escaping @MainActor (String) -> Void) async throws -> EditedDiagram {
        if shouldFail { throw Failure() }
        let edited = mermaid + "\n" + instruction
        return EditedDiagram(mermaid: edited, svg: "<svg>\(edited)</svg>")
    }
}

@MainActor struct UnusedVoiceInput: VoiceInstructionInput {
    func start(onPartialText: @escaping @MainActor (String) -> Void) throws {}
    func stopAndTranscribe() async throws -> String { "" }
}

func temporaryLibraryURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("termaid-tests-\(UUID().uuidString)/library.json")
}
