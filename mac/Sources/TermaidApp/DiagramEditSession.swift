import Foundation

/// The draft behind the diagram editor. Each typed or spoken change runs through the diagram model on top of
/// the current draft; changes can be undone one at a time, and nothing reaches the library until Save.
@MainActor final class DiagramEditSession: InstructionSession {
    @Published var title: String
    @Published private(set) var previewSVG: String
    @Published private(set) var appliedChanges: [String] = []

    let itemID: UUID
    private let original: LibraryItem
    private let editor: DiagramEditing
    private let library: DiagramLibrary
    private var drafts: [RenderedDiagram]

    init(item: LibraryItem, editor: DiagramEditing, voice: VoiceInstructionInput, library: DiagramLibrary) {
        original = item
        itemID = item.id
        title = item.title
        previewSVG = item.svg
        drafts = [RenderedDiagram(mermaid: item.mermaid, svg: item.svg)]
        self.editor = editor
        self.library = library
        super.init(voice: voice)
    }

    var canUndo: Bool { activity == .idle && !appliedChanges.isEmpty }
    var canSave: Bool {
        let newTitle = Self.trimmed(title)
        return activity == .idle && !newTitle.isEmpty && (!appliedChanges.isEmpty || newTitle != original.title)
    }

    func undo() {
        guard canUndo else { return }
        drafts.removeLast()
        appliedChanges.removeLast()
        previewSVG = drafts.last!.svg
        clearError()
    }

    func save() {
        guard canSave, let current = drafts.last else { return }
        let description = ([original.description] + appliedChanges).joined(separator: " ")
        library.update(itemID, title: title, description: description, mermaid: current.mermaid, svg: current.svg)
    }

    override var runningLabel: String { "Redrawing…" }

    override func perform(_ change: String, generation: Int) async throws {
        guard let current = drafts.last else { return }
        let edited = try await editor.edit(current.mermaid, instruction: change) { [weak self] svg in
            guard let self, self.isCurrent(generation) else { return }
            self.previewSVG = svg
        }
        guard isCurrent(generation) else { return }
        drafts.append(edited)
        appliedChanges.append(change)
        previewSVG = edited.svg
    }

    override func didFail(_ change: String) {
        previewSVG = drafts.last?.svg ?? previewSVG
    }
}
