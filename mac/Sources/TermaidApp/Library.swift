import Foundation

struct LibraryItem: Codable, Identifiable, Equatable {
    let id: UUID; let title: String; let description: String; let mermaid: String; let svg: String; let created: Date
}

/// Saved diagrams, newest first, persisted as JSON in Application Support.
@MainActor final class DiagramLibrary: ObservableObject {
    static let shared = DiagramLibrary()

    @Published private(set) var items: [LibraryItem] = []
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.items = Self.load(from: self.fileURL)
    }

    @discardableResult
    func add(title: String, description: String, mermaid: String, svg: String) -> LibraryItem {
        let item = LibraryItem(id: UUID(), title: title, description: description,
                               mermaid: mermaid, svg: svg, created: Date())
        items.insert(item, at: 0)
        save()
        return item
    }

    func remove(_ id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        save()
    }

    func rename(_ id: UUID, to title: String) {
        guard let old = items.first(where: { $0.id == id }) else { return }
        update(id, title: title, mermaid: old.mermaid, svg: old.svg)
    }

    /// Replaces an item's title and diagram in place, keeping its id, prompt and creation date. A blank title is ignored.
    func update(_ id: UUID, title: String, mermaid: String, svg: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        let old = items[index]
        items[index] = LibraryItem(id: old.id, title: trimmed, description: old.description,
                                   mermaid: mermaid, svg: svg, created: old.created)
        save()
    }

    // MARK: - Persistence

    private static func defaultFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("termaid/library.json")
    }

    private static func load(from url: URL) -> [LibraryItem] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([LibraryItem].self, from: data)
        } catch {
            // Keep the unreadable file aside so the next save doesn't silently destroy it.
            let backup = url.deletingLastPathComponent().appendingPathComponent("library.corrupt.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            NSLog("termaid: library.json was unreadable (\(error)); moved to \(backup.lastPathComponent)")
            return []
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(items).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("termaid: failed to save library: \(error)")
        }
    }
}
