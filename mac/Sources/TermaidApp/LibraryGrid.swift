import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Grid

struct LibraryGridView: View {
    @ObservedObject var highlight: LibraryHighlight
    @ObservedObject private var library = DiagramLibrary.shared
    @Binding var selection: UUID?
    let open: (LibraryItem) -> Void
    @FocusState private var focused: Bool
    @State private var columns = 3

    private static let minTile: CGFloat = 250
    private static let gap: CGFloat = 20

    var body: some View {
        let groups = DateGroup.make(library.items)
        VStack(alignment: .leading, spacing: 0) {
            header
            if groups.isEmpty {
                empty
            } else {
                ScrollViewReader { proxy in
                    BouncyScrollView {
                        LazyVStack(alignment: .leading, spacing: 30) {
                            ForEach(groups) { group in
                                VStack(alignment: .leading, spacing: 14) {
                                    Text(group.id.uppercased())
                                        .font(Obsidian.font(11, .semibold))
                                        .tracking(1.2)
                                        .foregroundStyle(Obsidian.muted)
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.minTile), spacing: Self.gap, alignment: .top)],
                                              alignment: .leading, spacing: Self.gap) {
                                        ForEach(group.items) { item in tile(item) }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                        .background(GeometryReader { geo in
                            Color.clear.onAppear { measure(geo.size.width) }
                                .onChange(of: geo.size.width) { _, w in measure(w) }
                        })
                    }
                    .onChange(of: selection) { _, id in
                        guard let id else { return }
                        withAnimation(.spring(duration: 0.5, bounce: 0.3)) { proxy.scrollTo(id) }
                    }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-columns) }
        .onKeyPress(.downArrow) { move(columns) }
        .onKeyPress(.space) { openSelected() }
        .onKeyPress(.return) { openSelected() }
        .onKeyPress(characters: ["c"]) { press in
            guard press.modifiers.contains(.command), let item = selected else { return .ignored }
            Actions.copyMermaid(item)
            return .handled
        }
        .onTapGesture { selection = nil }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Library")
                .font(Obsidian.font(24, .semibold))
                .foregroundStyle(Obsidian.fg)
            Text(library.items.count == 1 ? "1 diagram" : "\(library.items.count) diagrams")
                .font(Obsidian.font(13))
                .foregroundStyle(Obsidian.muted)
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 46)  // clears the title bar
        .padding(.bottom, 18)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 30))
                .foregroundStyle(Obsidian.muted)
            Text("No diagrams yet")
                .font(Obsidian.font(15, .semibold))
                .foregroundStyle(Obsidian.fg)
            Text("Hold ⌥ Space and describe a flow, or press ⌥ T to type one.")
                .font(Obsidian.font(13))
                .foregroundStyle(Obsidian.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tile(_ item: LibraryItem) -> some View {
        LibraryTile(item: item,
                    selected: selection == item.id,
                    highlighted: highlight.highlightedID == item.id,
                    open: { open(item) })
            .id(item.id)
            .onTapGesture(count: 2) { open(item) }
            .simultaneousGesture(TapGesture().onEnded { selection = item.id; focused = true })
            .onDrag { Actions.dragProvider(item) }
            .contextMenu {
                Button("Open") { open(item) }
                Button("Copy Mermaid") { Actions.copyMermaid(item) }
                Button("Copy Image") { Actions.copyImage(item) }
                Button("Export PNG…") { Actions.export(item, svg: false) }
                Button("Export SVG…") { Actions.export(item, svg: true) }
                Divider()
                Button("Rename…") { Actions.rename(item) }
                Button("Delete", role: .destructive) { library.remove(item.id) }
            }
    }

    // MARK: Keyboard

    private var flat: [LibraryItem] { DateGroup.make(library.items).flatMap(\.items) }
    private var selected: LibraryItem? { selection.flatMap { id in library.items.first { $0.id == id } } }

    private func measure(_ width: CGFloat) {
        let usable = width - 64
        columns = max(1, Int((usable + Self.gap) / (Self.minTile + Self.gap)))
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        let items = flat
        guard !items.isEmpty else { return .ignored }
        guard let current = selection, let index = items.firstIndex(where: { $0.id == current }) else {
            selection = items[0].id
            return .handled
        }
        selection = items[min(max(index + delta, 0), items.count - 1)].id
        return .handled
    }

    private func openSelected() -> KeyPress.Result {
        guard let item = selected else { return .ignored }
        open(item)
        return .handled
    }
}

struct LibraryTile: View {
    let item: LibraryItem
    let selected: Bool
    let highlighted: Bool
    let open: () -> Void
    @State private var hovering = false
    @State private var scale: CGFloat = 1
    @State private var toast: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Obsidian.canvas  // same ground as the detail view
                SVGImage(id: item.id, svg: item.svg)
                    .padding(16)
                    .scaleEffect(hovering ? 1.04 : 1)
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .bottomLeading) { kindTag.padding(10) }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    TileAction(symbol: "chevron.left.forwardslash.chevron.right", label: "Copy Mermaid",
                               confirms: true) { Actions.copyMermaid(item); show("Mermaid copied") }
                    TileAction(symbol: "photo", label: "Copy image",
                               confirms: true) { Actions.copyImage(item); show("Image copied") }
                    TileAction(symbol: "arrow.up.left.and.arrow.down.right", label: "Open") { open() }
                }
                .padding(10)
                .opacity(hovering ? 1 : 0)
                .offset(y: hovering ? 0 : -4)
            }
            .overlay(alignment: .bottomTrailing) {
                if let toast {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark").font(.system(size: 9.5, weight: .bold)).foregroundStyle(Obsidian.green)
                        Text(toast).font(Obsidian.font(11, .semibold)).foregroundStyle(Obsidian.fg)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .overlay(Capsule().stroke(Obsidian.green.opacity(0.5)))
                    .padding(10)
                    .transition(.opacity.combined(with: .offset(y: 4)))
                }
            }
            .animation(.easeOut(duration: 0.18), value: toast)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ringColor, lineWidth: selected ? 2 : 1))
            .shadow(color: selected ? Obsidian.deepBlue.opacity(0.45) : .black.opacity(0.4), radius: selected ? 12 : 6, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(Obsidian.font(13.5, .semibold))
                    .foregroundStyle(Obsidian.fg)
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(LibraryFormat.relativeText(item.created, now: context.date))
                        .font(Obsidian.font(11.5))
                        .foregroundStyle(Obsidian.muted)
                }
            }
            .padding(.horizontal, 2)
        }
        .scaleEffect(scale)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.18), value: hovering)
        .animation(.easeOut(duration: 0.15), value: selected)
        .onAppear { if highlighted { springIn() } }
        .onChange(of: highlighted) { _, on in if on { springIn() } }
    }

    private var ringColor: Color {
        if selected { return Obsidian.skyBlue }
        return hovering ? Color.white.opacity(0.22) : Obsidian.border.opacity(0.7)
    }

    private var kindTag: some View {
        Text(LibraryFormat.kind(item.mermaid))
            .font(Obsidian.font(10.5, .semibold))
            .foregroundStyle(Obsidian.muted)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .overlay(Capsule().stroke(Obsidian.border.opacity(0.8)))
    }

    private func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if toast == message { toast = nil }
        }
    }

    private func springIn() {
        scale = 0.92
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { scale = 1 }
    }
}

/// A small round button shown over a tile on hover. Hovered, it widens into a pill with its name;
/// clicked (when it copies), its icon turns into a green tick for a moment.
struct TileAction: View {
    let symbol: String
    let label: String
    var confirms = false
    let action: () -> Void
    @State private var hovering = false
    @State private var done = false

    var body: some View {
        Button {
            action()
            guard confirms else { return }
            done = true
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                done = false
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: done ? "checkmark" : symbol)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(done ? Obsidian.green : .white)
                    .contentTransition(.symbolEffect(.replace))
                if hovering {
                    Text(label)
                        .font(Obsidian.font(11, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, hovering ? 10 : 0)
            .frame(minWidth: 26, minHeight: 26)
            .background(Capsule().fill(hovering ? Color(white: 0.16) : Color.black.opacity(0.7)))
            .overlay(Capsule().stroke(Color.white.opacity(hovering ? 0.25 : 0.15)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(label)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.15), value: done)
    }
}

struct SVGImage: View {
    let id: UUID
    let svg: String

    var body: some View {
        if let image = SVGCache.image(id: id, svg: svg) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 28))
                .foregroundStyle(Obsidian.muted)
        }
    }
}

