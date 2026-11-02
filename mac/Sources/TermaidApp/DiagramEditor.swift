import Foundation
import TermaidCore

/// A drawn diagram: the Mermaid to store and the SVG to show.
struct RenderedDiagram: Equatable {
    let mermaid: String
    let svg: String
}

/// Applies a plain-language change ("remove the cache") to a saved diagram with the diagram model.
@MainActor protocol DiagramEditing {
    /// `onStep` gets the SVG after each sentence of the instruction, on the main actor.
    func edit(_ mermaid: String, instruction: String,
              onStep: @escaping @MainActor (String) -> Void) async throws -> RenderedDiagram
}

@MainActor struct EngineDiagramEditor: DiagramEditing {
    let models: ModelStore

    func edit(_ mermaid: String, instruction: String,
              onStep: @escaping @MainActor (String) -> Void) async throws -> RenderedDiagram {
        let engine = try await models.engine()
        let edited = try await engine.editStreaming(mermaid, instruction: instruction) { _, svg in
            Task { @MainActor in onStep(svg) }
        }
        let svg = try await Task.detached { try engine.toSvg(edited) }.value
        return RenderedDiagram(mermaid: edited, svg: svg)
    }
}
