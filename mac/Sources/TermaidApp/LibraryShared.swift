import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Helpers

@MainActor enum LibraryFormat {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    static let full: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static func relativeText(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        return relative.localizedString(for: date, relativeTo: now)
    }

    /// "Flowchart", "Sequence", … from the Mermaid header.
    static func kind(_ mermaid: String) -> String {
        let first = mermaid.split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased() ?? ""
        switch first {
        case "flowchart", "graph": return "Flowchart"
        case "sequencediagram": return "Sequence"
        case "classdiagram": return "Class"
        case "statediagram", "statediagram-v2": return "State"
        case "erdiagram": return "Entity"
        case "gantt": return "Gantt"
        case "pie": return "Pie"
        case "mindmap": return "Mindmap"
        case "timeline": return "Timeline"
        default: return "Diagram"
        }
    }
}

/// Newest first, in buckets by day.
struct DateGroup: Identifiable {
    let id: String
    let items: [LibraryItem]

    static func make(_ items: [LibraryItem], now: Date = Date()) -> [DateGroup] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        func label(_ date: Date) -> String {
            let day = cal.startOfDay(for: date)
            let days = cal.dateComponents([.day], from: day, to: today).day ?? 0
            switch days {
            case ..<1: return "Today"
            case 1: return "Yesterday"
            case 2..<7: return "This week"
            case 7..<30: return "This month"
            default: return "Earlier"
            }
        }
        var groups: [DateGroup] = []
        for item in items.sorted(by: { $0.created > $1.created }) {
            let name = label(item.created)
            if let last = groups.last, last.id == name {
                groups[groups.count - 1] = DateGroup(id: name, items: last.items + [item])
            } else {
                groups.append(DateGroup(id: name, items: [item]))
            }
        }
        return groups
    }
}

/// Rasterised SVG images, cached per item so grids don't re-parse on every redraw.
@MainActor enum SVGCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(id: UUID, svg: String) -> NSImage? {
        // The SVG's hash is part of the key so an edited diagram never shows its old rendering.
        let key = "\(id.uuidString)-\(svg.hashValue)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(data: Data(svg.utf8)) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// A 2x PNG of the diagram, for copying, dragging and export.
    static func png(id: UUID, svg: String) -> Data? {
        guard let image = image(id: id, svg: svg) else { return nil }
        let size = image.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
                                         pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

@MainActor enum Actions {
    static func copyMermaid(_ item: LibraryItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.mermaid, forType: .string)
    }

    static func copyImage(_ item: LibraryItem) {
        guard let png = SVGCache.png(id: item.id, svg: item.svg) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
    }

    /// The format is chosen in-app (the Export popover or the context menu); the panel only picks where.
    @discardableResult
    static func export(_ item: LibraryItem, svg: Bool) -> Bool {
        let panel = NSSavePanel()
        panel.title = svg ? "Export SVG" : "Export PNG"
        panel.prompt = "Export"
        panel.nameFieldStringValue = item.title
        panel.allowedContentTypes = [svg ? .svg : .png]
        panel.isExtensionHidden = false
        panel.appearance = NSAppearance(named: .darkAqua)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let data = svg ? Data(item.svg.utf8) : SVGCache.png(id: item.id, svg: item.svg)
        guard let data, (try? data.write(to: url, options: .atomic)) != nil else { return false }
        return true
    }

    static func dragProvider(_ item: LibraryItem) -> NSItemProvider {
        let provider = NSItemProvider()
        let id = item.id, svg = item.svg
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { done in
            Task { @MainActor in done(SVGCache.png(id: id, svg: svg), nil) }
            return nil
        }
        provider.suggestedName = item.title
        return provider
    }

    static func rename(_ item: LibraryItem) {
        let alert = NSAlert()
        alert.messageText = "Rename diagram"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: item.title)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            DiagramLibrary.shared.rename(item.id, to: field.stringValue)
        }
    }
}

/// The soft light behind the content, like the diagrams' own spotlight.
struct Spotlight: View {
    var body: some View {
        ZStack {
            Obsidian.canvas
            RadialGradient(colors: [Color.white.opacity(0.06), .clear], center: .init(x: 0.5, y: 0),
                           startRadius: 0, endRadius: 620)
        }
        .ignoresSafeArea()
    }
}

