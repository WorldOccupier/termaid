import Foundation
import TermaidCore

/// Turns Mermaid source into SVG, throwing when the source doesn't parse.
protocol MermaidRendering: Sendable {
    func svg(for mermaid: String) throws -> String
}

/// Renders through the same bundled engine.js as diagram generation, without loading the language model:
/// `toSvg` never asks the model for anything, so the engine gets a stand-in that refuses completions.
final class EngineMermaidRenderer: MermaidRendering, @unchecked Sendable {
    static let shared = EngineMermaidRenderer()

    private let lock = NSLock()
    private var engine: EmbeddedEngine?

    func svg(for mermaid: String) throws -> String {
        try loadedEngine().toSvg(mermaid)
    }

    private func loadedEngine() throws -> EmbeddedEngine {
        lock.lock(); defer { lock.unlock() }
        if let engine { return engine }
        let created = try EmbeddedEngine(model: RenderOnlyModel())
        engine = created
        return created
    }
}

private struct RenderOnlyModel: TextCompleting {
    func complete(system: String, user: String) async throws -> String {
        throw RenderOnlyError()
    }
}

private struct RenderOnlyError: LocalizedError {
    var errorDescription: String? { "The diagram editor renders Mermaid only" }
}
