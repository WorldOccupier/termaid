import Foundation
import Testing
@testable import TermaidApp

@Suite struct ModelDownloaderTests {
    @Test func movesTheDownloadIntoANewFolder() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("source.gguf")
        try Data("weights".utf8).write(to: source)
        let destination = dir.appendingPathComponent("nested/model.gguf")

        try await ModelDownloader(source: source, destination: destination) { _ in }.download()

        #expect(try String(contentsOf: destination, encoding: .utf8) == "weights")
    }
}
