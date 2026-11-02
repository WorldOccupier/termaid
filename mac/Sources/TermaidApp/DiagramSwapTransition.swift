import SwiftUI

/// Stepping between diagrams: the old one slips away blurred and shrinking, the new one springs in from the
/// side it came from with a blue glow that fades as it settles.
extension AnyTransition {
    /// `direction` is +1 for next (enters from the right) and -1 for previous (enters from the left).
    static func diagramSwap(direction: CGFloat) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(active: SwapPose(offset: 90 * direction, scale: 0.82, blur: 10, opacity: 0, glow: 1, tilt: 4 * direction),
                                 identity: .settled),
            removal: .modifier(active: SwapPose(offset: -70 * direction, scale: 0.9, blur: 8, opacity: 0, glow: 0, tilt: -3 * direction),
                               identity: .settled))
    }
}

private struct SwapPose: ViewModifier {
    let offset: CGFloat
    let scale: CGFloat
    let blur: CGFloat
    let opacity: Double
    let glow: Double
    let tilt: Double

    static let settled = SwapPose(offset: 0, scale: 1, blur: 0, opacity: 1, glow: 0, tilt: 0)

    func body(content: Content) -> some View {
        content
            .shadow(color: Obsidian.skyBlue.opacity(0.55 * glow), radius: 30 * glow)
            .scaleEffect(scale)
            .rotation3DEffect(.degrees(tilt), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .offset(x: offset)
            .blur(radius: blur)
            .opacity(opacity)
    }
}
