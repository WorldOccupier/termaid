import Foundation
import JavaScriptCore

public struct EngineError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

/// Runs termaid's TypeScript engine (bundled as engine.js by `npm run build:engine`) in
/// JavaScriptCore, so prompts, retries, checks and Mermaid validation stay shared with the CLI.
public final class EmbeddedEngine: @unchecked Sendable {
    private let model: TextCompleting
    // All JavaScript runs on this queue; promise jobs drain when each call back into JS returns.
    let queue = DispatchQueue(label: "termaid.engine")
    let context: JSContext
    let engine: JSValue

    public init(model: TextCompleting, script: String? = nil) throws {
        self.model = model
        context = JSContext()!
        context.evaluateScript(try script ?? Self.bundledScript())
        engine = context.objectForKeyedSubscript("termaidEngine")
        if let exception = context.exception { throw EngineError(message: "engine.js failed to load: \(exception)") }
    }

    public func convert(_ description: String) async throws -> String {
        try await call("convert", description)
    }

    /// The model's diagram as JSON (`{direction, boxes, edges}`), before it becomes Mermaid.
    public func describe(_ description: String) async throws -> String {
        try await call("describe", description)
    }

    public func toSvg(_ mermaid: String) throws -> String {
        try queue.sync {
            let svg = engine.invokeMethod("toSvg", withArguments: [mermaid])
            if let exception = context.exception {
                context.exception = nil
                throw EngineError(message: exception.toString())
            }
            return svg!.toString()
        }
    }

    private func call(_ method: String, _ description: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                let onSuccess: @convention(block) (String) -> Void = { continuation.resume(returning: $0) }
                let onFailure: @convention(block) (JSValue) -> Void = {
                    continuation.resume(throwing: EngineError(message: $0.objectForKeyedSubscript("message")?.toString() ?? $0.toString()))
                }
                let promise = engine.invokeMethod(method, withArguments: [description, hostCompletion()])
                promise?.invokeMethod("then", withArguments: [onSuccess, onFailure])
            }
        }
    }

    /// The `HostCompletion` the engine calls: a JS promise settled once the Swift model replies.
    func hostCompletion() -> JSValue {
        // Weak: the context holds this block, so a strong capture would keep the engine (and the
        // model's Metal buffers, which llama.cpp asserts are freed before exit) alive forever.
        let complete: @convention(block) (String, String) -> JSValue = { [weak self] system, user in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(newPromiseIn: self.context) { resolve, reject in
                Task {
                    do {
                        let reply = try await self.model.complete(system: system, user: user)
                        self.queue.async { resolve?.call(withArguments: [reply]) }
                    } catch {
                        self.queue.async { reject?.call(withArguments: [error.localizedDescription]) }
                    }
                }
            }
        }
        return JSValue(object: complete, in: context)
    }

    private static func bundledScript() throws -> String {
        guard let url = Bundle.module.url(forResource: "engine", withExtension: "js") else {
            throw EngineError(message: "engine.js missing; run `npm run build:engine`")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
