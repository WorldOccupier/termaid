import AVFoundation
import AppKit
import Foundation
import TermaidCore

/// Loads the two models once, in the background, and tells the setup window and the capsule how far along each is.
@MainActor
final class ModelStore: ObservableObject {
    enum Status: Equatable {
        case waiting
        case notDownloaded
        case downloading(Double)
        case loading
        case ready
        case missing
        case failed(String)

        var isReady: Bool { self == .ready }
    }

    static let shared = ModelStore()

    @Published private(set) var speech: Status = ParakeetTranscriber.isDownloaded ? .waiting : .notDownloaded
    @Published private(set) var diagram: Status = .waiting
    @Published private(set) var microphone: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)

    private var speechTask: Task<ParakeetTranscriber, Error>?
    private var diagramTask: Task<EmbeddedEngine, Error>?

    private static let modelPathKey = "modelPath"
    private static let setupDoneKey = "setupDone"

    var allReady: Bool { speech.isReady && diagram.isReady }

    /// Setup shows on first launch, and again whenever something it would fix is missing.
    var needsSetup: Bool {
        !UserDefaults.standard.bool(forKey: Self.setupDoneKey)
            || !ParakeetTranscriber.isDownloaded
            || !FileManager.default.fileExists(atPath: Self.modelPath)
    }

    func markSetupDone() {
        UserDefaults.standard.set(true, forKey: Self.setupDoneKey)
    }

    /// `$TERMAID_MODEL`, then a file picked in setup, then the default location.
    static var modelPath: String {
        if let override = ProcessInfo.processInfo.environment["TERMAID_MODEL"], !override.isEmpty {
            return override
        }
        if let picked = UserDefaults.standard.string(forKey: modelPathKey), !picked.isEmpty {
            return picked
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("termaid/model.gguf").path
    }

    /// Loads whatever is already on this Mac. Never downloads; that waits for `downloadSpeech()`.
    /// Safe to call repeatedly; finished or running loads are kept.
    func prepare() {
        if speechTask == nil, ParakeetTranscriber.isDownloaded { startSpeech() }
        if diagramTask == nil { startDiagram() }
    }

    /// The user pressed Download in setup.
    func downloadSpeech() {
        if speechTask == nil { startSpeech() }
    }

    func transcriber() async throws -> ParakeetTranscriber {
        if speechTask == nil, ParakeetTranscriber.isDownloaded { startSpeech() }
        guard let task = speechTask else {
            throw UserFacingError(message: "Speech model not downloaded — open Setup from the menu")
        }
        return try await task.value
    }

    func engine() async throws -> EmbeddedEngine {
        if diagramTask == nil { startDiagram() }
        guard let task = diagramTask else {
            throw UserFacingError(message: "Diagram model missing — open Setup from the menu")
        }
        return try await task.value
    }

    func chooseModelFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose the termaid diagram model"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: "gguf") ?? .data]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: Self.modelPathKey)
        diagramTask = nil
        startDiagram()
    }

    func retry() {
        if case .failed = speech { speechTask = nil; startSpeech() }
        if case .failed = diagram { diagramTask = nil; startDiagram() }
    }

    func requestMicrophone() {
        if microphone == .denied || microphone == .restricted {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in
                self.microphone = AVCaptureDevice.authorizationStatus(for: .audio)
            }
        }
    }

    func refreshMicrophone() {
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    // MARK: - Loading

    private func startSpeech() {
        speech = ParakeetTranscriber.isDownloaded ? .loading : .downloading(0)
        let task = Task<ParakeetTranscriber, Error> {
            try await ParakeetTranscriber.load { fraction in
                Task { @MainActor in
                    guard !ModelStore.shared.speech.isReady else { return }
                    ModelStore.shared.speech = fraction.map { .downloading($0) } ?? .loading
                }
            }
        }
        speechTask = task
        Task {
            do {
                _ = try await task.value
                speech = .ready
            } catch {
                speech = .failed(error.localizedDescription)
            }
        }
    }

    private func startDiagram() {
        let path = Self.modelPath
        guard FileManager.default.fileExists(atPath: path) else {
            diagram = .missing
            return
        }
        diagram = .loading
        let task = Task.detached(priority: .userInitiated) {
            try EmbeddedEngine(model: LlamaModel(path: path))
        }
        diagramTask = task
        Task {
            do {
                _ = try await task.value
                diagram = .ready
            } catch {
                diagram = .failed(error.localizedDescription)
                diagramTask = nil
            }
        }
    }
}
