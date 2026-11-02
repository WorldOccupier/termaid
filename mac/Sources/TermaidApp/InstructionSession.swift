import Foundation

/// Progress lines shared by the capsule, the editor and the composer.
enum StatusLabel {
    static let listening = "Listening…"
    static let transcribing = "Transcribing…"
    static let thinking = "Thinking…"
    static let loadingDiagramModel = "Loading diagram model…"
}

/// What the editor and the new-diagram composer share: an instruction typed, or spoken and transcribed, then run
/// through the diagram model one at a time. Subclasses say what running one means in `perform(_:generation:)`.
@MainActor class InstructionSession: ObservableObject {
    enum Activity: Equatable { case idle, listening, transcribing, running }

    @Published var instruction = ""
    @Published private(set) var activity = Activity.idle
    @Published private(set) var errorMessage: String?
    /// The instruction the model is working on, shown until it lands or fails.
    @Published private(set) var pendingInstruction: String?

    private let voice: VoiceInstructionInput
    /// Bumped on cancel, so a model reply that arrives afterwards is dropped.
    private var generation = 0

    private static let trailingAudio = Duration.milliseconds(350)
    private static let transcriptPause = Duration.milliseconds(600)

    init(voice: VoiceInstructionInput) {
        self.voice = voice
    }

    var canApply: Bool { activity == .idle && !Self.trimmed(instruction).isEmpty }
    /// Typing is blocked while the spoken words are transcribed or the model runs.
    var isBusy: Bool { activity == .transcribing || activity == .running }

    /// The progress line for the current activity, if any.
    var statusLabel: String? {
        switch activity {
        case .idle: return nil
        case .listening: return StatusLabel.listening
        case .transcribing: return StatusLabel.transcribing
        case .running: return runningLabel
        }
    }

    func applyInstruction() {
        guard canApply else { return }
        let text = Self.trimmed(instruction)
        instruction = ""
        run(text)
    }

    /// Click once to start talking, again (or Return) to stop; the full transcript shows in the box, then is applied.
    func toggleListening() {
        switch activity {
        case .idle: startListening()
        case .listening: finishListening()
        default: break
        }
    }

    func cancel() {
        generation += 1
        if activity == .listening { Task { _ = try? await voice.stopAndTranscribe() } }
        pendingInstruction = nil
        activity = .idle
    }

    // MARK: - For subclasses

    var runningLabel: String { StatusLabel.thinking }

    /// Runs one instruction. Check `isCurrent(generation)` before changing state after each await.
    func perform(_ instruction: String, generation: Int) async throws {
        preconditionFailure("Subclasses run instructions")
    }

    /// Called when `perform` throws, before the error shows, to put back whatever it changed.
    func didFail(_ instruction: String) {}

    func isCurrent(_ generation: Int) -> Bool { generation == self.generation }

    func clearError() { errorMessage = nil }

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Running an instruction

    private func startListening() {
        errorMessage = nil
        do {
            try voice.start { [weak self] partial in
                guard let self, self.activity == .listening else { return }
                self.instruction = partial
            }
            instruction = ""
            activity = .listening
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishListening() {
        activity = .transcribing
        let gen = generation
        Task {
            do {
                // Keep recording briefly so the last word isn't clipped when Return comes right after it.
                try await Task.sleep(for: Self.trailingAudio)
                let spoken = Self.trimmed(try await voice.stopAndTranscribe())
                guard isCurrent(gen) else { return }
                guard !spoken.isEmpty else { return fail("Didn't catch that") }
                instruction = spoken
                // Let the full sentence be seen in the box before it moves on.
                try await Task.sleep(for: Self.transcriptPause)
                guard isCurrent(gen) else { return }
                instruction = ""
                run(spoken)
            } catch {
                guard isCurrent(gen) else { return }
                fail(error.localizedDescription)
            }
        }
    }

    private func run(_ text: String) {
        activity = .running
        errorMessage = nil
        pendingInstruction = text
        let gen = generation
        Task {
            do {
                try await perform(text, generation: gen)
                guard isCurrent(gen) else { return }
                pendingInstruction = nil
                activity = .idle
            } catch {
                guard isCurrent(gen) else { return }
                didFail(text)
                fail(error.localizedDescription)
            }
        }
    }

    private func fail(_ message: String) {
        pendingInstruction = nil
        activity = .idle
        errorMessage = message
    }
}
