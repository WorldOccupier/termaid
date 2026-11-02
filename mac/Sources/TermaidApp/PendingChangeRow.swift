import SwiftUI

/// The change being redrawn: empty until the flight lands, then a burst and a shimmer until the model finishes.
struct PendingChangeRow: View {
    let text: String
    let landed: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "sparkle")
                .foregroundStyle(Obsidian.skyBlue)
                .symbolEffect(.pulse, isActive: landed)
                .overlay { LandingBurst(fired: landed) }
            Text(text)
                .foregroundStyle(Obsidian.fg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .flightAnchor(FlightAnchor.target)
                .modifier(Shimmer(active: landed))
                .opacity(landed ? 1 : 0)
        }
    }
}

/// A ring and sparks that spread from the icon the moment the text lands.
private struct LandingBurst: View {
    let fired: Bool
    private static let sparkCount = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(Obsidian.skyBlue, lineWidth: 1.5)
                .scaleEffect(fired ? 2.6 : 0.2)
                .opacity(fired ? 0 : 0.9)
            ForEach(0..<Self.sparkCount, id: \.self) { index in
                let angle = Angle.degrees(Double(index) / Double(Self.sparkCount) * 360)
                Circle()
                    .fill(Color.white)
                    .frame(width: 2.5, height: 2.5)
                    .offset(x: fired ? 16 * cos(angle.radians) : 0, y: fired ? 16 * sin(angle.radians) : 0)
                    .opacity(fired ? 0 : 1)
            }
        }
        .frame(width: 12, height: 12)
        .animation(.easeOut(duration: 0.6), value: fired)
        .allowsHitTesting(false)
    }
}

/// A band of light sweeping across the text while the diagram redraws.
private struct Shimmer: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -0.6

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                LinearGradient(colors: [.clear, Obsidian.skyBlue.opacity(0.9), .clear],
                               startPoint: UnitPoint(x: phase, y: 0.5), endPoint: UnitPoint(x: phase + 0.6, y: 0.5))
                    .mask(content)
                    .onAppear {
                        withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.2 }
                    }
            }
        }
    }
}
