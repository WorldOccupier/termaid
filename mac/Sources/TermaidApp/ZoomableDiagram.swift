import AppKit
import SwiftUI

/// Wraps a fitted diagram so it can be zoomed with the − / + buttons or a pinch, and panned by
/// dragging once zoomed. The content is laid out larger rather than scaled, so the SVG stays sharp.
struct ZoomableDiagram<Content: View>: View {
    /// Dragging the diagram out of the window, offered only at 100% so it never fights panning.
    var exportDrag: (() -> NSItemProvider)?
    @ViewBuilder let content: () -> Content

    static var zoomRange: ClosedRange<CGFloat> { 1...4 }
    private static var zoomStep: CGFloat { 1.25 }

    @State private var zoom: CGFloat = 1
    @State private var pinchStartZoom: CGFloat?
    @State private var pan: CGSize = .zero
    @State private var dragStartPan: CGSize?

    var body: some View {
        GeometryReader { geo in
            content()
                .frame(width: geo.size.width * zoom, height: geo.size.height * zoom)
                .offset(pan)
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(panGesture(in: geo.size), including: zoom > 1 ? .all : .subviews)
                .simultaneousGesture(pinchGesture(in: geo.size))
                .modifier(ExportDrag(provider: zoom > 1 ? nil : exportDrag))
                .overlay(alignment: .bottomTrailing) { controls(in: geo.size) }
        }
        .clipped()
    }

    private func controls(in size: CGSize) -> some View {
        HStack(spacing: 2) {
            ZoomButton(symbol: "minus", help: "Zoom out") { setZoom(zoom / Self.zoomStep, in: size) }
                .disabled(zoom <= Self.zoomRange.lowerBound)
            Button { setZoom(1, in: size) } label: {
                Text("\(Int((zoom * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .frame(width: 40, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reset zoom")
            ZoomButton(symbol: "plus", help: "Zoom in") { setZoom(zoom * Self.zoomStep, in: size) }
                .disabled(zoom >= Self.zoomRange.upperBound)
        }
        .foregroundStyle(.white)
        .padding(2)
        .background(Capsule().fill(Color.black.opacity(0.6)))
        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
        .padding(10)
    }

    private func pinchGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStartZoom ?? zoom
                pinchStartZoom = start
                applyZoom(start * value.magnification, in: size)
            }
            .onEnded { _ in pinchStartZoom = nil }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = dragStartPan ?? pan
                dragStartPan = start
                pan = clamped(CGSize(width: start.width + value.translation.width,
                                     height: start.height + value.translation.height), zoom: zoom, in: size)
            }
            .onEnded { _ in dragStartPan = nil }
    }

    private func setZoom(_ target: CGFloat, in size: CGSize) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { applyZoom(target, in: size) }
    }

    private func applyZoom(_ target: CGFloat, in size: CGSize) {
        zoom = min(max(target, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        pan = clamped(pan, zoom: zoom, in: size)
    }

    /// Keeps the zoomed diagram covering the view, so panning never reveals empty space past its edge.
    private func clamped(_ offset: CGSize, zoom: CGFloat, in size: CGSize) -> CGSize {
        let maxX = size.width * (zoom - 1) / 2
        let maxY = size.height * (zoom - 1) / 2
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }
}

private struct ZoomButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct ExportDrag: ViewModifier {
    let provider: (() -> NSItemProvider)?

    func body(content: Content) -> some View {
        if let provider { content.onDrag(provider) } else { content }
    }
}
