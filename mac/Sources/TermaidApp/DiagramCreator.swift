import Foundation
import TermaidCore

/// Draws a new diagram from a plain-language description ("build, then test, then ship") with the diagram model.
@MainActor protocol DiagramCreating {
    /// False while the model still has to load, which can take a while on first use.
    var isModelLoaded: Bool { get }
    /// `onSentences` gets the description split the way the model reads it, before any drawing;
    /// `onStep` gets the step index and the SVG after each sentence. Both run on the main actor.
    func create(from description: String,
                onSentences: @escaping @MainActor ([String]) -> Void,
                onStep: @escaping @MainActor (Int, String) -> Void) async throws -> RenderedDiagram
}

extension DiagramCreating {
    var workingLabel: String { isModelLoaded ? StatusLabel.thinking : StatusLabel.loadingDiagramModel }
}

@MainActor struct EngineDiagramCreator: DiagramCreating {
    let models: ModelStore

    var isModelLoaded: Bool { models.diagram.isReady }

    func create(from description: String,
                onSentences: @escaping @MainActor ([String]) -> Void,
                onStep: @escaping @MainActor (Int, String) -> Void) async throws -> RenderedDiagram {
        let engine = try await models.engine()
        let sentences = try await Task.detached { try engine.sentences(description) }.value
        guard !sentences.isEmpty else { throw UserFacingError(message: "Didn't catch that") }
        onSentences(sentences)
        let mermaid = try await engine.convertStreaming(description) { index, svg in
            Task { @MainActor in onStep(index, svg) }
        }
        let svg = try await Task.detached { try engine.toSvg(mermaid) }.value
        return RenderedDiagram(mermaid: mermaid, svg: svg)
    }
}

enum DiagramTitle {
    static let untitled = "Untitled flow"

    /// The first sentence's first five words, capitalized, without trailing punctuation.
    static func from(_ sentence: String) -> String {
        let words = sentence.split(whereSeparator: { $0.isWhitespace }).prefix(5).joined(separator: " ")
        let trimmed = words.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
        guard let first = trimmed.first else { return untitled }
        return String(first).uppercased() + String(trimmed.dropFirst())
    }
}
