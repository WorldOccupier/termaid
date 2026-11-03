import Foundation

/// Downloads one file to a destination, reporting progress, and moves it into place only once complete
/// so an interrupted download never leaves a partial model where the app would try to load it.
final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let diagramModelURL = URL(string: "https://huggingface.co/VatsaIsHere/termaid/resolve/main/termaid.gguf")!

    private let source: URL
    private let destination: URL
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var movedFile = false

    init(source: URL, destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.source = source
        self.destination = destination
        self.progress = progress
    }

    func download(configuration: URLSessionConfiguration = .default) async throws {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: source).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten written: Int64, totalBytesExpectedToWrite expected: Int64) {
        guard expected > 0 else { return }
        progress(Double(written) / Double(expected))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            finish(UserFacingError(message: "Download failed (HTTP \(status))"))
            return
        }
        do {
            try moveIntoPlace(location)
            movedFile = true
        } catch {
            finish(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error ?? (movedFile ? nil : UserFacingError(message: "Download failed")))
    }

    private func moveIntoPlace(_ location: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if files.fileExists(atPath: destination.path) { try files.removeItem(at: destination) }
        try files.moveItem(at: location, to: destination)
    }

    private func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
}
