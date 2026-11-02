import SwiftUI

/// A vertical ScrollView that rubber-bands when scrolling runs into the top or bottom, like pull-to-refresh on a
/// phone: the content keeps going past the edge by an amount that matches the scroll speed, then springs back.
/// A mouse wheel gets no rubber band from macOS, so this adds one for every kind of scroll.
struct BouncyScrollView<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var stretch: CGFloat = 0
    @State private var lastOffset: CGFloat?

    private static var maxStretch: CGFloat { 60 }
    private static var speedToStretch: CGFloat { 4 }

    var body: some View {
        if #available(macOS 15, *) {
            // The whole scroll view moves, not its content: offsetting lazily loaded content made tiles that were
            // scrolled away redraw over the header and fly back in. Clipping keeps the stretch inside the grid.
            ScrollView { content }
                .scrollBounceBehavior(.always)
                .onScrollGeometryChange(for: EdgeState.self, of: EdgeState.init) { _, state in
                    handle(state)
                }
                .offset(y: stretch)
                .clipped()
        } else {
            ScrollView { content }
        }
    }

    @available(macOS 15, *)
    private func handle(_ state: EdgeState) {
        defer { lastOffset = state.offset }
        // The first reading is where the grid opens, not a scroll, so there is nothing to bounce off yet.
        guard let lastOffset else { return }
        let speed = state.offset - lastOffset
        // A trackpad already rubber-bands past the edge on its own; only a scroll that stops flush at the edge
        // (a mouse wheel, or a trackpad flick that macOS clamps) gets the extra bounce, so it never doubles up.
        let hitTop = abs(state.offset - state.top) < 1 && lastOffset > state.top + 1 && speed < 0
        let hitBottom = abs(state.offset - state.bottom) < 1 && lastOffset < state.bottom - 1 && speed > 0
        guard hitTop || hitBottom else { return }
        // Past the top the content drops down; past the bottom it lifts up.
        let amount = min(Self.maxStretch, max(18, abs(speed) * Self.speedToStretch))
        snapBack(from: hitTop ? amount : -amount)
    }

    private func snapBack(from amount: CGFloat) {
        withAnimation(.easeOut(duration: 0.14)) { stretch = amount } completion: {
            withAnimation(.spring(duration: 0.7, bounce: 0.5)) { stretch = 0 }
        }
    }
}

/// Where the scroll is, and the offsets at which it sits flush against the top and bottom.
@available(macOS 15, *)
private struct EdgeState: Equatable {
    let offset: CGFloat
    let top: CGFloat
    let bottom: CGFloat

    init(_ geometry: ScrollGeometry) {
        offset = geometry.contentOffset.y
        top = -geometry.contentInsets.top
        bottom = max(top, geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.bottom)
    }
}
