import Foundation

/// The new-diagram composer's state: a typed or spoken description, drawn one sentence at a time like the
/// capsule's card, then saved to the library. A failed description goes back into the box to fix and retry.
@MainActor final class DiagramCreateSession: InstructionSession {
    @Published private(set) var title = ""
    @Published private(set) var sentences: [String] = []
    @Published private(set) var currentStep = 0
    @Published private(set) var previewSVG: String?
    /// Bumped with each new drawing step, so the preview sweeps in again.
    @Published private(set) var previewRevision = 0
    @Published private(set) var createdItem: LibraryItem?

    /// Identifies this draft's renderings in the SVG cache.
    let draftID = UUID()
    private let creator: DiagramCreating
    private let library: DiagramLibrary

    init(creator: DiagramCreating, voice: VoiceInstructionInput, library: DiagramLibrary) {
        self.creator = creator
        self.library = library
        super.init(voice: voice)
    }

    /// From the moment the description is split into sentences: the composer grows into the drawing card.
    var isDrawing: Bool { !sentences.isEmpty }
    /// One description per session; once it's saved the composer closes.
    override var canApply: Bool { super.canApply && createdItem == nil }
    override var runningLabel: String { creator.workingLabel }

    override func perform(_ description: String, generation: Int) async throws {
        let diagram = try await creator.create(from: description, onSentences: { [weak self] sentences in
            guard let self, self.isCurrent(generation) else { return }
            self.beginDrawing(sentences)
        }, onStep: { [weak self] index, svg in
            guard let self, self.isCurrent(generation) else { return }
            self.showStep(index, svg: svg)
        })
        guard isCurrent(generation) else { return }
        showStep(sentences.count - 1, svg: diagram.svg)
        createdItem = library.add(title: title, description: description, mermaid: diagram.mermaid, svg: diagram.svg)
    }

    override func didFail(_ description: String) {
        clearDrawing()
        instruction = description
    }

    override func cancel() {
        super.cancel()
        clearDrawing()
    }

    private func beginDrawing(_ sentences: [String]) {
        self.sentences = sentences
        title = sentences.first.map(DiagramTitle.from) ?? DiagramTitle.untitled
        currentStep = 0
        previewSVG = nil
    }

    /// Steps only move forward; the same step arriving twice is ignored.
    private func showStep(_ index: Int, svg: String) {
        guard previewSVG == nil || index > currentStep else { return }
        currentStep = index
        previewSVG = svg
        previewRevision += 1
    }

    private func clearDrawing() {
        sentences = []
        previewSVG = nil
    }
}
