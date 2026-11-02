import SwiftUI

/// The Library's new-diagram sheet: a black capsule-style bar to type or say a flow, which grows into the
/// capsule's drawing card once the model starts drawing, shows "Saved to Library", then hands the diagram back.
struct NewDiagramComposer: View {
    @ObservedObject var session: DiagramCreateSession
    /// Called with the saved diagram, or nil when cancelled.
    let finish: (LibraryItem?) -> Void

    private static let composingWidth: CGFloat = 560
    private static let composingRadius: CGFloat = 22
    /// How long the saved card stays up before the Library highlights the new tile.
    private static let savedPause = Duration.milliseconds(1100)
    private static let idleHint = "Return to draw, or click the mic and say it. Esc cancels."

    var body: some View {
        ZStack(alignment: .top) {
            backdrop
            VStack(alignment: .trailing, spacing: 10) {
                shape
                SmallButton(symbol: "xmark", label: "Cancel", help: "Cancel (Esc)", size: 26, action: close)
                    .keyboardShortcut(.cancelAction)
                    // Solid, so the dimmed grid doesn't show through it.
                    .background(Capsule().fill(Obsidian.surface))
                    .opacity(session.createdItem == nil ? 1 : 0)
            }
            .padding(.top, 64)
            .padding(.horizontal, 24)
        }
        .task(id: session.createdItem?.id) { await finishAfterSaving() }
    }

    private var backdrop: some View {
        Color.black.opacity(0.45)
            .contentShape(Rectangle())
            // Only an idle composer closes on a stray click, so a running description is never lost by accident.
            .onTapGesture { if session.activity == .idle { close() } }
    }

    /// One black shape that morphs from the composing bar into the drawing card, like the capsule does.
    private var shape: some View {
        let drawing = session.isDrawing
        let outline = RoundedRectangle(cornerRadius: drawing ? DiagramDrawingCard.cornerRadius : Self.composingRadius,
                                       style: .continuous)
        return ZStack {
            if drawing {
                drawingCard.transition(.composerLayer)
            } else {
                composing.transition(.composerLayer)
            }
        }
        .frame(maxWidth: drawing ? CapsuleMetrics.card.width : Self.composingWidth)
        .frame(height: drawing ? CapsuleMetrics.card.height : nil)
        .clipShape(outline)
        .background(outline.fill(Color.black).shadow(color: .black.opacity(0.55), radius: 22, y: 10))
        .animation(DiagramDrawingCard.growCurve, value: drawing)
    }

    private var composing: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                DiagramBadge()
                Text("New diagram")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            InstructionField(session: session, prompts: .create, showsPendingInstruction: true)
            InstructionStatusLine(session: session, idleHint: Self.idleHint)
        }
        .padding(16)
    }

    private var drawingCard: some View {
        DiagramDrawingCard(title: session.title, sentences: session.sentences, currentStep: session.currentStep,
                           image: session.previewSVG.flatMap { SVGCache.image(id: session.draftID, svg: $0) },
                           revision: session.previewRevision, saved: session.createdItem != nil)
            .contentShape(Rectangle())
            .onTapGesture { if let item = session.createdItem { finish(item) } }
    }

    /// Esc, Cancel or a click outside. Once saved, closing just shows the new diagram sooner.
    private func close() {
        if let item = session.createdItem { return finish(item) }
        session.cancel()
        finish(nil)
    }

    private func finishAfterSaving() async {
        guard let item = session.createdItem else { return }
        try? await Task.sleep(for: Self.savedPause)
        guard !Task.isCancelled else { return }
        finish(item)
    }
}

private extension AnyTransition {
    /// Content fades in once the shape has mostly grown, and out quickly, as in the capsule.
    static let composerLayer = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.3).delay(0.16)),
        removal: .opacity.animation(.easeOut(duration: 0.12)))
}
