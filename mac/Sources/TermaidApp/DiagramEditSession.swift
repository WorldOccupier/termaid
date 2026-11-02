import Foundation

/// The draft behind the diagram editor. Each typed or spoken change runs through the diagram model on top of
/// the current draft; changes can be undone one at a time, and nothing reaches the library until Save.
@MainActor final class DiagramEditSession: ObservableObject {
    enum Activity: Equatable { case idle, listening, transcribing, applying }

    @Published var title: String
    @Published var instruction = ""
    @Published private(set) var previewSVG: String
    @Published private(set) var appliedChanges: [String] = []
    @Published private(set) var activity = Activity.idle
    @Published private(set) var errorMessage: String?
    /// The change the model is working on, shown in CHANGES until it lands or fails.
    @Published private(set) var pendingChange: String?

    let itemID: UUID
    private let original: LibraryItem
    private let editor: DiagramEditing
    private let voice: VoiceInstructionInput
    private let library: DiagramLibrary
    private var drafts: [EditedDiagram]
    /// Bumped on cancel, so a model reply that arrives afterwards is dropped.
    private var generation = 0

    init(item: LibraryItem, editor: DiagramEditing, voice: VoiceInstructionInput, library: DiagramLibrary) {
        original = item
        itemID = item.id
        title = item.title
        previewSVG = item.svg
        drafts = [EditedDiagram(mermaid: item.mermaid, svg: item.svg)]
        self.editor = editor
        self.voice = voice
        self.library = library
    }

    var canApply: Bool { activity == .idle && !trimmed(instruction).isEmpty }
    var canUndo: Bool { activity == .idle && !appliedChanges.isEmpty }
    var canSave: Bool {
        activity == .idle && !trimmed(title).isEmpty && (!appliedChanges.isEmpty || trimmed(title) != original.title)
    }

    func applyInstruction() {
        guard canApply else { return }
        let change = trimmed(instruction)
        instruction = ""
        run(change)
    }

    /// Click once to start talking, again (or Return) to stop; the full transcript shows in the box, then is applied.
    func toggleListening() {
        switch activity {
        case .idle: startListening()
        case .listening: finishListening()
        default: break
        }
    }

    func undo() {
        guard canUndo else { return }
        drafts.removeLast()
        appliedChanges.removeLast()
        previewSVG = drafts.last!.svg
        errorMessage = nil
    }

    func save() {
        guard canSave, let current = drafts.last else { return }
        let description = ([original.description] + appliedChanges).joined(separator: " ")
        library.update(itemID, title: title, description: description, mermaid: current.mermaid, svg: current.svg)
    }

    func cancel() {
        generation += 1
        if activity == .listening { Task { _ = try? await voice.stopAndTranscribe() } }
        pendingChange = nil
        activity = .idle
    }

    // MARK: - Running a change

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

    private static let trailingAudio = Duration.milliseconds(350)
    private static let transcriptPause = Duration.milliseconds(600)

    private func finishListening() {
        activity = .transcribing
        let gen = generation
        Task {
            do {
                // Keep recording briefly so the last word isn't clipped when Return comes right after it.
                try await Task.sleep(for: Self.trailingAudio)
                let spoken = trimmed(try await voice.stopAndTranscribe())
                guard gen == generation else { return }
                guard !spoken.isEmpty else { return fail("Didn't catch that") }
                instruction = spoken
                // Let the full sentence be seen in the box before it moves to CHANGES.
                try await Task.sleep(for: Self.transcriptPause)
                guard gen == generation else { return }
                instruction = ""
                run(spoken)
            } catch {
                guard gen == generation else { return }
                fail(error.localizedDescription)
            }
        }
    }

    private func run(_ change: String) {
        guard let current = drafts.last else { return }
        activity = .applying
        errorMessage = nil
        pendingChange = change
        let gen = generation
        Task {
            do {
                let edited = try await editor.edit(current.mermaid, instruction: change) { [weak self] svg in
                    guard let self, gen == self.generation else { return }
                    self.previewSVG = svg
                }
                guard gen == generation else { return }
                finish(change, edited)
            } catch {
                guard gen == generation else { return }
                previewSVG = current.svg
                fail(error.localizedDescription)
            }
        }
    }

    private func finish(_ change: String, _ edited: EditedDiagram) {
        pendingChange = nil
        drafts.append(edited)
        appliedChanges.append(change)
        previewSVG = edited.svg
        activity = .idle
    }

    private func fail(_ message: String) {
        pendingChange = nil
        activity = .idle
        errorMessage = message
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
