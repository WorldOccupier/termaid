import Foundation

/// The draft behind the diagram editor: re-renders the Mermaid shortly after each change, keeps the
/// last good rendering when the source is broken, and writes the result back to the library on save.
@MainActor final class DiagramEditSession: ObservableObject {
    @Published var title: String
    @Published var mermaid: String { didSet { if mermaid != oldValue { scheduleRender() } } }
    @Published private(set) var previewSVG: String
    @Published private(set) var renderError: String?
    @Published private(set) var isRendering = false

    let itemID: UUID
    private let renderer: MermaidRendering
    private let library: DiagramLibrary
    private let debounce: Duration
    private var renderTask: Task<Void, Never>?

    init(item: LibraryItem, renderer: MermaidRendering, library: DiagramLibrary,
         debounce: Duration = .milliseconds(300)) {
        itemID = item.id
        title = item.title
        mermaid = item.mermaid
        previewSVG = item.svg
        self.renderer = renderer
        self.library = library
        self.debounce = debounce
    }

    /// Saving is allowed only when the preview matches the source, so the stored SVG is never stale or broken.
    var canSave: Bool {
        renderError == nil && !isRendering && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save() {
        guard canSave else { return }
        library.update(itemID, title: title, mermaid: mermaid, svg: previewSVG)
    }

    func cancel() {
        renderTask?.cancel()
    }

    private func scheduleRender() {
        renderTask?.cancel()
        isRendering = true
        let source = mermaid, renderer = renderer, delay = debounce
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let result = await Task.detached { Result { try renderer.svg(for: source) } }.value
            guard !Task.isCancelled else { return }
            self?.apply(result)
        }
    }

    private func apply(_ result: Result<String, Error>) {
        isRendering = false
        switch result {
        case .success(let svg):
            previewSVG = svg
            renderError = nil
        case .failure(let error):
            renderError = Self.shortMessage(error)
        }
    }

    /// The engine prefixes parser errors with "Error: Generated Mermaid is invalid (syntax): "; the editor only needs the rest.
    static func shortMessage(_ error: Error) -> String {
        let message = error.localizedDescription
        guard let range = message.range(of: "is invalid ("), let colon = message[range.upperBound...].range(of: "): ")
        else { return message }
        return String(message[colon.upperBound...])
    }
}
