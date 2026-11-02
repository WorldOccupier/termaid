import Foundation
import JavaScriptCore

extension EmbeddedEngine {
    /// Sentences as the engine splits them (same splitter the model loop uses).
    public func sentences(_ description: String) throws -> [String] {
        try queue.sync {
            let json = engine.invokeMethod("sentences", withArguments: [description])
            if let exception = context.exception {
                context.exception = nil
                throw EngineError(message: exception.toString())
            }
            guard let data = json?.toString().data(using: .utf8),
                  let list = try? JSONDecoder().decode([String].self, from: data) else {
                throw EngineError(message: "sentences() returned an unexpected value")
            }
            return list
        }
    }

    /// Runs the per-sentence loop; after each sentence calls onStep(index, svg) with the diagram so far.
    /// Returns the final Mermaid source. `onStep` runs on the engine queue, so hop to main before touching UI.
    public func convertStreaming(_ description: String,
                                 onStep: @escaping @Sendable (_ index: Int, _ svg: String) -> Void) async throws -> String {
        try await stream("convertSteps", [description], onStep: onStep)
    }

    /// Applies a plain-language change to Mermaid this engine generated, one sentence at a time, and returns
    /// the updated Mermaid. `onStep` behaves as in `convertStreaming`.
    public func editStreaming(_ mermaid: String, instruction: String,
                              onStep: @escaping @Sendable (_ index: Int, _ svg: String) -> Void) async throws -> String {
        try await stream("editSteps", [mermaid, instruction], onStep: onStep)
    }

    private func stream(_ method: String, _ arguments: [String],
                        onStep: @escaping @Sendable (Int, String) -> Void) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                // JS numbers arrive as Double; convert to Int only after the engine has produced them.
                let step: @convention(block) (Double, String) -> Void = { index, svg in
                    onStep(Int(index), svg)
                }
                let onSuccess: @convention(block) (String) -> Void = { continuation.resume(returning: $0) }
                let onFailure: @convention(block) (JSValue) -> Void = {
                    continuation.resume(throwing: EngineError(message: $0.objectForKeyedSubscript("message")?.toString() ?? $0.toString()))
                }
                let promise = engine.invokeMethod(method, withArguments: arguments + [hostCompletion(), step])
                if let exception = context.exception {
                    context.exception = nil
                    continuation.resume(throwing: EngineError(message: exception.toString()))
                    return
                }
                promise?.invokeMethod("then", withArguments: [onSuccess, onFailure])
            }
        }
    }
}
