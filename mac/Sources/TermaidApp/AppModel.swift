import AppKit
import Foundation
import TermaidCore

/// An error whose message is shown in the capsule as-is.
struct UserFacingError: Error {
    let message: String
}

/// The capsule's state machine: idle, listening or typing, working, then a card that draws the diagram and saves it.
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case idle, listening, typing, working, card, saved
    }

    static let levelCount = 18

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var hintVisible = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var workingLabel = StatusLabel.transcribing
    @Published private(set) var levels = [Float](repeating: 0, count: AppModel.levelCount)
    @Published var typedText = ""
    /// The words recognized so far while listening; empty until the first ones arrive.
    @Published private(set) var liveTranscript = ""
    @Published private(set) var sentences: [String] = []
    @Published private(set) var currentStep = 0
    @Published private(set) var title = ""
    @Published private(set) var svgImage: NSImage?
    @Published private(set) var svgRevision = 0

    private let recorder = VoiceRecorder()
    private var recording = false
    private let models = ModelStore.shared
    private let creator: DiagramCreating
    private lazy var live = LiveTranscript(recorder: recorder, models: models)
    private var workTask: Task<Void, Never>?
    /// Bumped whenever the current flow is abandoned, so late callbacks from it are ignored.
    private var generation = 0
    private var lastSavedID: UUID?

    init(creator: DiagramCreating) {
        self.creator = creator
        recorder.onLevel = { [weak self] level in
            Task { @MainActor in self?.pushLevel(level) }
        }
    }

    /// The black shape's size for the current phase. The panel is always the card's size.
    var shapeSize: CGSize {
        switch phase {
        case .idle: return errorMessage == nil ? CapsuleMetrics.pill : CapsuleMetrics.bar
        case .listening, .typing, .working: return CapsuleMetrics.bar
        case .card, .saved: return CapsuleMetrics.card
        }
    }

    // MARK: - Entry points

    func flashHint() {
        guard phase == .idle else { return }
        hintVisible = true
    }

    func voiceDown() {
        guard phase != .working, phase != .listening else { return }
        reset()
        do {
            try recorder.start()
        } catch {
            fail(UserFacingError(message: "Microphone unavailable: \(error.localizedDescription)"))
            return
        }
        recording = true
        levels = [Float](repeating: 0, count: Self.levelCount)
        live.start { [weak self] text in
            guard let self, self.phase == .listening else { return }
            self.liveTranscript = text
        }
        phase = .listening
    }

    func voiceUp() {
        guard recording else { return }
        recording = false
        live.stop()
        phase = .working
        workingLabel = models.speech.isReady ? StatusLabel.transcribing : "Loading speech model…"
        let gen = generation
        workTask = Task { await self.finishVoice(gen: gen) }
    }

    func startTyping() {
        guard phase != .working, phase != .listening else { return }
        reset()
        phase = .typing
    }

    func submitTyped() {
        guard phase == .typing else { return }
        let text = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            escape()
            return
        }
        reset()
        phase = .working
        workingLabel = StatusLabel.thinking
        let gen = generation
        workTask = Task { await self.describe(text, gen: gen) }
    }

    /// Esc, a click outside, or a new hotkey press: abandons whatever is on screen.
    func escape() {
        switch phase {
        case .idle:
            hintVisible = false
            errorMessage = nil
            return
        case .listening:
            recording = false
            Task { _ = try? await recorder.stop() }
        default:
            break
        }
        reset()
        phase = .idle
    }

    /// Clicking the saved card opens it in the Library.
    func openCard() {
        guard phase == .saved else { return }
        LibraryWindow.show(highlighting: lastSavedID)
        escape()
    }

    // MARK: - Pipeline

    private func finishVoice(gen: Int) async {
        do {
            let url = try await recorder.stop()
            let text = try await transcribe(url)
            await describe(text, gen: gen)
        } catch {
            guard gen == generation else { return }
            fail(error)
        }
    }

    private func transcribe(_ url: URL) async throws -> String {
        let parakeet = try await models.transcriber()
        workingLabel = StatusLabel.transcribing
        return try await parakeet.transcribe(fileAt: url)
    }

    private func describe(_ raw: String, gen: Int) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard gen == generation else { return }
        guard !text.isEmpty else {
            fail(UserFacingError(message: "Didn't catch that"))
            return
        }
        workingLabel = creator.workingLabel
        do {
            let diagram = try await creator.create(from: text, onSentences: { [weak self] sents in
                self?.showCard(sents, gen: gen)
            }, onStep: { [weak self] index, svg in
                self?.receiveStep(index, svg: svg, gen: gen)
            })
            guard gen == generation else { return }
            receiveStep(sentences.count - 1, svg: diagram.svg, gen: gen)
            save(diagram, description: text)
        } catch {
            guard gen == generation else { return }
            fail(error)
        }
    }

    private func showCard(_ sents: [String], gen: Int) {
        guard gen == generation else { return }
        sentences = sents
        title = DiagramTitle.from(sents[0])
        currentStep = 0
        svgImage = nil
        phase = .card
    }

    private func save(_ diagram: RenderedDiagram, description: String) {
        let item = DiagramLibrary.shared.add(title: title, description: description,
                                             mermaid: diagram.mermaid, svg: diagram.svg)
        lastSavedID = item.id
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagram.mermaid, forType: .string)
        // The saved card stays until the user clicks elsewhere or presses Esc.
        phase = .saved
    }

    private func receiveStep(_ index: Int, svg: String, gen: Int) {
        // Steps only move forward; the same step arriving twice is ignored.
        guard gen == generation, svgImage == nil || index > currentStep,
              let image = NSImage(data: Data(svg.utf8)) else { return }
        currentStep = index
        svgImage = image
        svgRevision += 1
    }

    // MARK: - Helpers

    private func pushLevel(_ level: Float) {
        guard recording else { return }
        levels.removeFirst()
        levels.append(level)
    }

    /// Abandons the current flow: late results from it are dropped.
    private func reset() {
        generation += 1
        workTask?.cancel()
        workTask = nil
        hintVisible = false
        errorMessage = nil
        typedText = ""
        liveTranscript = ""
        live.stop()
    }

    private func fail(_ error: Error) {
        reset()
        recording = false
        phase = .idle
        errorMessage = (error as? UserFacingError)?.message ?? error.localizedDescription
    }
}
