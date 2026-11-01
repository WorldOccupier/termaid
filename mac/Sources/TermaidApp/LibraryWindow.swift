import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Shared UI state for the Library window: which item to highlight next.
@MainActor final class LibraryHighlight: ObservableObject {
    @Published var highlightedID: UUID?
    @Published var openID: UUID?
}

/// One dark Library window, created on first use and reused afterwards.
@MainActor enum LibraryWindow {
    private static var window: NSWindow?
    private static let highlight = LibraryHighlight()
    private static let appMode = LibraryAppMode(app: NSApp)

    static func show(highlighting id: UUID?, opening openID: UUID? = nil) {
        highlight.highlightedID = id
        highlight.openID = openID
        if window == nil { window = makeWindow() }
        guard let window else { return }
        appMode.enter()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private static func makeWindow() -> NSWindow {
        let w = InsetButtonsWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Library"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(red: 5 / 255, green: 5 / 255, blue: 6 / 255, alpha: 1)
        w.isReleasedWhenClosed = false
        w.delegate = appMode
        w.minSize = NSSize(width: 660, height: 460)
        w.center()
        w.contentView = NSHostingView(rootView: LibraryRootView(highlight: highlight))
        return w
    }
}

/// Nudges the close/minimise/zoom buttons in from the corner; AppKit re-lays them out, so this re-applies after each layout.
final class InsetButtonsWindow: NSWindow {
    static let inset = CGPoint(x: 8, y: 4)

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (i, kind) in kinds.enumerated() {
            guard let button = standardWindowButton(kind), let bar = button.superview else { continue }
            let x = 7 + Self.inset.x + CGFloat(i) * 20
            let y = bar.bounds.height - button.frame.height - 7 - Self.inset.y
            if button.frame.origin != CGPoint(x: x, y: y) { button.setFrameOrigin(CGPoint(x: x, y: y)) }
        }
    }
}

// MARK: - Root

struct LibraryRootView: View {
    @ObservedObject var highlight: LibraryHighlight
    @ObservedObject private var library = DiagramLibrary.shared
    @State private var selection: UUID?
    @State private var openID: UUID?

    private var openItem: LibraryItem? { openID.flatMap { id in library.items.first { $0.id == id } } }

    var body: some View {
        ZStack {
            Spotlight()
            if let item = openItem {
                LibraryDetailView(item: item, items: ordered, open: open, close: close)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(1)
            } else {
                LibraryGridView(highlight: highlight, selection: $selection, open: open)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 660, minHeight: 460)
        .preferredColorScheme(.dark)
        .onChange(of: highlight.highlightedID) { _, id in
            guard let id else { return }
            selection = id
            close()
        }
        .onAppear {
            if let id = highlight.highlightedID { selection = id }
            if let id = highlight.openID { openID = id }
        }
    }

    private var ordered: [LibraryItem] { DateGroup.make(library.items).flatMap(\.items) }

    private func open(_ item: LibraryItem) {
        selection = item.id
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { openID = item.id }
    }

    private func close() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { openID = nil }
    }
}

