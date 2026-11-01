import SwiftUI

/// The editing card beside the live preview: title, Mermaid source, the latest render error, Cancel and Save.
struct DiagramEditorPanel: View {
    @ObservedObject var session: DiagramEditSession
    let save: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Title")
            titleField
            label("Mermaid")
            sourceEditor
            status
            buttons
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Obsidian.border.opacity(0.6)))
        .padding(.trailing, 16)
        .padding(.bottom, 16)
    }

    private var titleField: some View {
        TextField("Title", text: $session.title)
            .textFieldStyle(.plain)
            .font(Obsidian.font(14, .semibold))
            .foregroundStyle(Obsidian.fg)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(fieldBackground)
    }

    private var sourceEditor: some View {
        MermaidSourceEditor(text: $session.mermaid)
            .padding(4)
            .frame(maxHeight: .infinity)
            .background(fieldBackground)
    }

    /// One line, so a long parser message never pushes the buttons around.
    @ViewBuilder private var status: some View {
        if let error = session.renderError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(Obsidian.font(11.5))
                .foregroundStyle(Obsidian.rose)
                .lineLimit(2)
                .help(error)
        } else {
            Label(session.isRendering ? "Rendering…" : "Preview is up to date",
                  systemImage: session.isRendering ? "arrow.triangle.2.circlepath" : "checkmark")
                .font(Obsidian.font(11.5))
                .foregroundStyle(Obsidian.muted)
        }
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            ActionRow(symbol: "xmark", title: "Cancel", help: "Discard changes (Esc)", action: cancel)
            ActionRow(symbol: "checkmark", title: "Save", help: "Save changes (⌘S)", action: save)
                .disabled(!session.canSave)
                .opacity(session.canSave ? 1 : 0.4)
                .keyboardShortcut("s", modifiers: .command)
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Obsidian.border.opacity(0.7)))
    }

    private func label(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Obsidian.font(10.5, .semibold))
            .tracking(1.1)
            .foregroundStyle(Obsidian.muted)
    }
}

/// The draft's latest good rendering; observes the session so it redraws as the source changes.
struct DiagramEditPreview: View {
    @ObservedObject var session: DiagramEditSession

    var body: some View {
        SVGImage(id: session.itemID, svg: session.previewSVG)
    }
}
