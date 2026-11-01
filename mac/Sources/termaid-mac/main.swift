import Foundation
import TermaidCore

// Spike CLI for the native engine:
//   termaid-mac transcribe <file.wav>
//   termaid-mac diagram <model.gguf> "description"
//   termaid-mac eval <model.gguf> <descriptions.txt>   (JSON lines for scripts/compare-engines.ts)
let usage = "usage: termaid-mac transcribe <file.wav> | diagram <model.gguf> <text> | eval <model.gguf> <descriptions.txt>"

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func timing(_ step: String, since start: ContinuousClock.Instant) -> String {
    "\(step) in \(String(format: "%.2f", seconds(since: start)))s"
}

func seconds(since start: ContinuousClock.Instant) -> Double {
    let elapsed = ContinuousClock.now - start
    return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
}

func transcribe(_ path: String) async throws {
    var start = ContinuousClock.now
    let transcriber = try await ParakeetTranscriber.load()
    log(timing("model loaded", since: start))
    start = ContinuousClock.now
    let text = try await transcriber.transcribe(fileAt: URL(fileURLWithPath: path))
    log(timing("transcribed", since: start))
    print(text)
}

func diagram(modelPath: String, description: String) async throws {
    let engine = try EmbeddedEngine(model: try LlamaModel(path: modelPath))
    let start = ContinuousClock.now
    print(try await engine.convert(description), terminator: "")
    log(timing("diagram", since: start))
}

func evaluate(modelPath: String, descriptionsPath: String) async throws {
    let engine = try EmbeddedEngine(model: try LlamaModel(path: modelPath))
    let descriptions = try String(contentsOfFile: descriptionsPath, encoding: .utf8).split(separator: "\n").map(String.init)
    for description in descriptions where !description.isEmpty {
        let start = ContinuousClock.now
        var result: [String: Any] = ["description": description]
        do {
            let state = try await engine.describe(description)
            result["state"] = try JSONSerialization.jsonObject(with: Data(state.utf8))
        } catch {
            result["error"] = error.localizedDescription
        }
        result["seconds"] = seconds(since: start)
        print(String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self))
    }
}

let arguments = CommandLine.arguments.dropFirst().map { $0 }
do {
    switch (arguments.first, arguments.count) {
    case ("transcribe", 2): try await transcribe(arguments[1])
    case ("diagram", 3): try await diagram(modelPath: arguments[1], description: arguments[2])
    case ("eval", 3): try await evaluate(modelPath: arguments[1], descriptionsPath: arguments[2])
    default:
        log(usage)
        exit(2)
    }
} catch {
    log("termaid-mac: \(error.localizedDescription)")
    exit(1)
}
