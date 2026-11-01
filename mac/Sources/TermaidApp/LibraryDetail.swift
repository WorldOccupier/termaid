import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Detail

/// Slides in from the right over the grid: the diagram large, with what was said and the Mermaid beside it.
struct LibraryDetailView: View {
    let item: LibraryItem
    let items: [LibraryItem]
    let open: (LibraryItem) -> Void
    let close: () -> Void
    var makeEditSession: (LibraryItem) -> DiagramEditSession = { item in
        DiagramEditSession(item: item, renderer: EngineMermaidRenderer.shared, library: DiagramLibrary.shared)
    }
    @FocusState private var focused: Bool
    @State private var copied: String?
    @AppStorage("libraryInfoOpen") private var showInfo = false
    @State private var editSession: DiagramEditSession?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack(spacing: 0) {
                diagram
                if let editSession {
                    DiagramEditorPanel(session: editSession, save: saveEdit, cancel: cancelEdit)
                        .frame(width: 380)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else if showInfo {
                    sidePanel
                        .frame(width: 300)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Info toggle: the diagram gets the whole window until you ask for details.
            if editSession == nil {
                SmallButton(symbol: showInfo ? "info.circle.fill" : "info.circle",
                            help: showInfo ? "Hide info (I)" : "Show info (I)", size: 28, action: toggleInfo)
                    .padding(16)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onExitCommand { editSession == nil ? close() : cancelEdit() }
        .onKeyPress(.escape) { editSession == nil ? close() : cancelEdit(); return .handled }
        .onKeyPress(.space) { browsing { close() } }
        .onKeyPress(characters: ["i"]) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            return browsing { toggleInfo() }
        }
        .onKeyPress(characters: ["e"]) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            return browsing { startEdit() }
        }
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .onKeyPress(characters: ["c"]) { press in
            guard press.modifiers.contains(.command), editSession == nil else { return .ignored }
            copy("Mermaid") { Actions.copyMermaid(item) }
            return .handled
        }
    }

    /// While editing, the source pane gets the preview; otherwise the saved diagram, draggable out.
    private var diagram: some View {
        Group {
            if let editSession { DiagramEditPreview(session: editSession) } else { SVGImage(id: item.id, svg: item.svg) }
        }
            .padding(32)
            .id(item.id)
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrag { Actions.dragProvider(item) }
    }

    /// Runs a browsing shortcut only when not editing, so typing in the editor never triggers one.
    private func browsing(_ run: () -> Void) -> KeyPress.Result {
        guard editSession == nil else { return .ignored }
        run()
        return .handled
    }

    private func startEdit() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { editSession = makeEditSession(item) }
    }

    private func saveEdit() {
        guard let editSession, editSession.canSave else { return }
        editSession.save()
        endEdit()
    }

    private func cancelEdit() {
        editSession?.cancel()
        endEdit()
    }

    private func endEdit() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { editSession = nil }
        focused = true
    }

    private func toggleInfo() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { showInfo.toggle() }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            SmallButton(symbol: "chevron.left", help: "Back (Esc)", size: 28, action: close)

            Spacer()
            if editSession == nil {
                SmallButton(symbol: "pencil", label: "Edit", help: "Edit diagram (E)", size: 28, action: startEdit)
            }
            Text("\(position + 1) of \(items.count)")
                .font(Obsidian.font(13))
                .foregroundStyle(Obsidian.muted)
                .monospacedDigit()
            stepButton("chevron.left", -1)
            stepButton("chevron.right", 1)
        }
        .padding(.leading, 7 + InsetButtonsWindow.inset.x)  // left edge of the close button
        .padding(.trailing, 16)
        .frame(height: 28)
        .padding(.top, 30 + InsetButtonsWindow.inset.y)  // just under the traffic lights
        .padding(.bottom, 6)
    }

    /// A card that hugs its content. The actions sit above the prompt, so a long or short prompt never moves them.
    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
                .padding(.bottom, Self.panelSectionGap)
            panelDivider
            panelActions
                .padding(.vertical, Self.panelSectionGap)
            if !item.description.isEmpty {
                panelDivider
                panelPrompt
                    .padding(.top, Self.panelSectionGap)
            }
        }
        .padding(Self.panelPadding)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Obsidian.border.opacity(0.6)))
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.trailing, 16)
        .padding(.bottom, 16)
    }

    private static let panelPadding: CGFloat = 18
    private static let panelSectionGap: CGFloat = 16

    private var panelHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(Obsidian.font(18, .semibold))
                .foregroundStyle(Obsidian.fg)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                chip(LibraryFormat.kind(item.mermaid), symbol: "point.3.connected.trianglepath.dotted")
                chip(LibraryFormat.relativeText(item.created), symbol: "clock")
                    .help(LibraryFormat.full.string(from: item.created))
            }
        }
    }

    /// Copy and Save as two labelled rows, inspector-style: the label in a fixed column, equal-width pills beside it.
    private var panelActions: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                sectionLabel("Copy")
                HStack(spacing: 6) {
                    ActionRow(symbol: "chevron.left.forwardslash.chevron.right", title: "Mermaid", help: "Copy Mermaid code (⌘C)",
                              done: copied == "Mermaid", doneText: "Copied") {
                        copy("Mermaid") { Actions.copyMermaid(item) }
                    }
                    ActionRow(symbol: "photo", title: "Image", help: "Copy image",
                              done: copied == "Image", doneText: "Copied") {
                        copy("Image") { Actions.copyImage(item) }
                    }
                }
            }
            GridRow {
                sectionLabel("Save")
                HStack(spacing: 6) {
                    saveAction(svg: false)
                    saveAction(svg: true)
                }
            }
        }
    }

    private func saveAction(svg: Bool) -> some View {
        let format = svg ? "SVG" : "PNG"
        return ActionRow(symbol: "square.and.arrow.down", title: format, help: "Save as \(format)…",
                         done: copied == format, doneText: "Saved") {
            if Actions.export(item, svg: svg) { copy(format) {} }
        }
    }

    private var panelPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("You said")
            // Read-only, like a disabled field: selectable, never editable.
            Text(item.description)
                .font(Obsidian.font(13))
                .foregroundStyle(Obsidian.fg.opacity(0.85))
                .lineSpacing(3)
                .lineLimit(8)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Obsidian.border.opacity(0.7)))
        }
    }

    private var panelDivider: some View {
        Rectangle().fill(Obsidian.border.opacity(0.45)).frame(height: 1)
    }

    private func chip(_ text: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold))
            Text(text)
        }
        .font(Obsidian.font(11.5, .medium))
        .foregroundStyle(Obsidian.muted)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().stroke(Obsidian.border.opacity(0.8)))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Obsidian.font(10.5, .semibold))
            .tracking(1.1)
            .foregroundStyle(Obsidian.muted)
    }

    private func stepButton(_ symbol: String, _ delta: Int) -> some View {
        SmallButton(symbol: symbol, help: delta < 0 ? "Previous (←)" : "Next (→)", size: 28) { _ = step(delta) }
            .disabled(!canStep(delta))
            .opacity(canStep(delta) ? 1 : 0.35)
    }

    private var position: Int { items.firstIndex(where: { $0.id == item.id }) ?? 0 }

    private func canStep(_ delta: Int) -> Bool { editSession == nil && items.indices.contains(position + delta) }

    private func step(_ delta: Int) -> KeyPress.Result {
        guard canStep(delta) else { return .ignored }
        withAnimation(.easeOut(duration: 0.2)) { open(items[position + delta]) }
        return .handled
    }

    /// Runs a copy and briefly swaps that row's icon for a tick.
    private func copy(_ what: String, _ run: () -> Void) {
        run()
        copied = what
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if copied == what { copied = nil }
        }
    }
}

/// A compact pill: an icon, and optionally a short label. Used for every control in the detail view.
struct SmallButton: View {
    let symbol: String
    var label: String? = nil
    let help: String
    var done = false
    var fill = false  // stretch to share a row equally
    var size: CGFloat = 22
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.48, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                if let label { Text(label).font(Obsidian.font(11.5, .semibold)).lineLimit(1).fixedSize() }
            }
            .foregroundStyle(done ? Obsidian.green : (hovering && enabled ? Color.white : Obsidian.fg.opacity(0.85)))
            .padding(.horizontal, label == nil ? 0 : 9)
            .frame(minWidth: size, maxWidth: fill ? .infinity : nil, minHeight: size)
            .background(Capsule().fill(Color.white.opacity(hovering && enabled ? 0.12 : 0.06)))
            .overlay(Capsule().stroke(Obsidian.border.opacity(0.8)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// A small pill: grey icon and name, sharing its row equally with its siblings. Done swaps the icon for a green tick and the name for doneText.
struct ActionRow: View {
    let symbol: String
    let title: String
    var help = ""
    var done = false
    var doneText = "Done"
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: done ? "checkmark" : symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(done ? Obsidian.green : Obsidian.muted)
                Text(done ? doneText : title)
                    .font(Obsidian.font(11.5, .medium))
                    .foregroundStyle(done ? Obsidian.green : (hovering ? Obsidian.fg : Obsidian.fg.opacity(0.85)))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(Capsule().fill(Color.white.opacity(hovering ? 0.08 : 0.04)))
            .overlay(Capsule().strokeBorder(Obsidian.border.opacity(0.7)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: done)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
