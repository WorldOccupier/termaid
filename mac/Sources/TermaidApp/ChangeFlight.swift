import SwiftUI

/// Named frames the flight travels between: the instruction field and the pending row in CHANGES.
enum FlightAnchor {
    static let source = "flight.source"
    static let target = "flight.target"
}

struct FlightAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func flightAnchor(_ name: String) -> some View {
        anchorPreference(key: FlightAnchorKey.self, value: .bounds) { [name: $0] }
    }
}

/// A submitted change leaving the field and arcing up into CHANGES, glowing mid-flight with a fading comet trail.
struct ChangeFlight: View {
    let text: String
    let from: CGRect
    let to: CGRect
    let onLanded: () -> Void
    @State private var progress: CGFloat = 0

    private static let trailLength = 5

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Drawn back to front so the lead copy sits on top of its trail.
            ForEach((0..<Self.trailLength).reversed(), id: \.self) { index in
                FlightCopy(text: text, from: from, to: to, progress: progress, trailIndex: index)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.22)) { progress = 1 } completion: { onLanded() }
        }
    }
}

/// One copy of the flying text; copies further back in the trail lag, blur and fade.
private struct FlightCopy: View, Animatable {
    let text: String
    let from: CGRect
    let to: CGRect
    var progress: CGFloat
    let trailIndex: Int

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private static let lagPerCopy: CGFloat = 0.06
    private static let fieldTextInset = CGPoint(x: 12, y: 10)

    var body: some View {
        let t = localProgress
        let lift = sin(.pi * min(max(t, 0), 1))
        let position = pointOnArc(t)
        Text(text)
            .font(Obsidian.font(14 - 1.5 * min(t, 1), .medium))
            .foregroundStyle(trailIndex == 0 ? Color.white : Obsidian.skyBlue)
            .frame(width: to.width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .scaleEffect(1 + 0.08 * lift, anchor: .leading)
            .rotationEffect(.degrees(-3 * lift), anchor: .leading)
            .shadow(color: Obsidian.skyBlue.opacity(0.9 * lift), radius: 12 * lift)
            .shadow(color: Color.caretBlue.opacity(0.6 * lift), radius: 3 * lift)
            .blur(radius: CGFloat(trailIndex) * 1.6)
            .opacity(trailIndex == 0 ? 1 : 0.4 * lift / CGFloat(trailIndex))
            .offset(x: position.x, y: position.y)
    }

    private var localProgress: CGFloat {
        let lag = Self.lagPerCopy * CGFloat(trailIndex)
        return max(0, (progress - lag) / (1 - lag))
    }

    /// A quadratic curve that swings out to the left on its way up, so the text visibly travels rather than slides.
    private func pointOnArc(_ t: CGFloat) -> CGPoint {
        let start = CGPoint(x: from.minX + Self.fieldTextInset.x, y: from.minY + Self.fieldTextInset.y)
        let end = to.origin
        let control = CGPoint(x: min(start.x, end.x) - 40, y: (start.y + end.y) / 2)
        let u = 1 - t
        return CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                       y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
    }
}
