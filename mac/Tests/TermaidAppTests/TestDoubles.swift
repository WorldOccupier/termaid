import Foundation
@testable import TermaidApp

/// Appends each instruction to the Mermaid, or throws when told to.
@MainActor final class ScriptedDiagramEditor: DiagramEditing {
    struct Failure: LocalizedError { var errorDescription: String? { "model failed" } }
    var shouldFail = false

    func edit(_ mermaid: String, instruction: String,
              onStep: @escaping @MainActor (String) -> Void) async throws -> RenderedDiagram {
        if shouldFail { throw Failure() }
        let edited = mermaid + "\n" + instruction
        return RenderedDiagram(mermaid: edited, svg: "<svg>\(edited)</svg>")
    }
}

/// Splits the description into sentences at full stops and draws one step per sentence, or throws when told to.
/// With `holding` set it waits after splitting until `release()`, so a test can act mid-drawing.
@MainActor final class ScriptedDiagramCreator: DiagramCreating {
    struct Failure: LocalizedError { var errorDescription: String? { "model failed" } }
    var shouldFail = false
    var holding = false
    private(set) var finished = false
    let isModelLoaded = true

    func release() { holding = false }

    func create(from description: String,
                onSentences: @escaping @MainActor ([String]) -> Void,
                onStep: @escaping @MainActor (Int, String) -> Void) async throws -> RenderedDiagram {
        defer { finished = true }
        let sentences = description.split(separator: ".").map { $0.trimmingCharacters(in: .whitespaces) }
        onSentences(sentences)
        while holding { await Task.yield() }
        if shouldFail { throw Failure() }
        for index in sentences.indices { onStep(index, "<svg>\(index)</svg>") }
        let mermaid = "flowchart LR\n" + sentences.joined(separator: "\n")
        return RenderedDiagram(mermaid: mermaid, svg: "<svg>\(mermaid)</svg>")
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
