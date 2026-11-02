import SwiftUI

/// The editing card beside the live preview: title, the changes applied so far, a field to describe the next
/// one by text or voice, and Undo, Cancel and Save.
struct DiagramEditorPanel: View {
    @ObservedObject var session: DiagramEditSession
    let save: () -> Void
    let cancel: () -> Void
    /// The pending change whose flight has finished, so its row text can show.
    @State private var landedChange: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Title")
            titleField
            label("Changes")
            changeList
            InstructionField(session: session)
            InstructionStatusLine(session: session)
            buttons
        }
        .padding(18)
        .overlayPreferenceValue(FlightAnchorKey.self, flight)
        .onChange(of: session.pendingInstruction) { _, pending in if pending == nil { landedChange = nil } }
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
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Obsidian.border.opacity(0.7)))
    }

    private var changeList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if session.appliedChanges.isEmpty && session.pendingInstruction == nil {
                    Text("Say or type what to change. Each change redraws the diagram, and Undo steps back.")
                        .foregroundStyle(Obsidian.muted)
                }
                ForEach(Array(session.appliedChanges.enumerated()), id: \.offset) { index, change in
                    appliedRow(change, isNewest: index == session.appliedChanges.count - 1)
                }
                if let pending = session.pendingInstruction {
                    PendingChangeRow(text: pending, landed: landedChange == pending)
                }
            }
            .font(Obsidian.font(12.5))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    private func appliedRow(_ change: String, isNewest: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(isNewest ? Obsidian.green : Obsidian.muted)
                .symbolEffect(.bounce, value: isNewest ? session.appliedChanges.count : 0)
            Text(change).foregroundStyle(Obsidian.fg)
        }
    }

    @ViewBuilder private func flight(_ anchors: [String: Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            if let change = session.pendingInstruction, landedChange != change,
               let source = anchors[FlightAnchor.source], let target = anchors[FlightAnchor.target] {
                ChangeFlight(text: change, from: proxy[source], to: proxy[target]) { landedChange = change }
                    .id(change)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            ActionRow(symbol: "arrow.uturn.backward", title: "Undo", help: "Undo last change (⌘Z)", action: session.undo)
                .disabled(!session.canUndo)
                .opacity(session.canUndo ? 1 : 0.4)
                .keyboardShortcut("z", modifiers: .command)
            Spacer()
            ActionRow(symbol: "xmark", title: "Cancel", help: "Discard changes (Esc)", action: cancel)
            ActionRow(symbol: "checkmark", title: "Save", help: "Save changes (⌘S)", action: save)
                .disabled(!session.canSave)
                .opacity(session.canSave ? 1 : 0.4)
                .keyboardShortcut("s", modifiers: .command)
        }
    }

    private func label(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Obsidian.font(10.5, .semibold))
            .tracking(1.1)
            .foregroundStyle(Obsidian.muted)
    }
}

/// The draft's latest rendering; observes the session so it redraws after each change.
struct DiagramEditPreview: View {
    @ObservedObject var session: DiagramEditSession

    var body: some View {
        SVGImage(id: session.itemID, svg: session.previewSVG)
    }
}
