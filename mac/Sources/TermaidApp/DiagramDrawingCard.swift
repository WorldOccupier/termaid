import AppKit
import SwiftUI

/// The card a new diagram is drawn on: its title, the description with the sentence being drawn in white,
/// and the canvas sweeping each step in. Shared by the capsule and the Library's new-diagram composer.
struct DiagramDrawingCard: View {
    let title: String
    let sentences: [String]
    let currentStep: Int
    let image: NSImage?
    /// Bumped per drawing step so the canvas sweeps the new step in.
    let revision: Int
    let saved: Bool

    /// The springy curve the black shape grows into this card with.
    static let growCurve = Animation.timingCurve(0.3, 1.12, 0.45, 1, duration: 0.76)
    static let cornerRadius: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            transcript
            canvas
        }
        .padding(.top, 14)
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
    }

    private var header: some View {
        HStack(spacing: 8) {
            DiagramBadge()
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
            savedChip
        }
        .frame(height: 24)
        .padding(.horizontal, 2)
    }

    private var savedChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
            Text("Saved to Library")
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.okGreen)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(Color.okGreen.opacity(0.14)))
        .opacity(saved ? 1 : 0)
        .offset(y: saved ? 0 : 4)
        .animation(.easeOut(duration: 0.3), value: saved)
    }

    /// Each sentence is gray; the one being drawn turns white.
    private var transcript: some View {
        var line = Text("")
        for (index, sentence) in sentences.enumerated() {
            if index > 0 { line = line + Text(" ") }
            let current = index == currentStep
            line = line + Text(sentence).foregroundColor(current ? .white : Color(white: 0.56))
        }
        return line
            .font(.system(size: 13))
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .animation(.easeOut(duration: 0.35), value: currentStep)
    }

    private var canvas: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Obsidian.canvas)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
            RevealDiagram(image: image)
                .id(revision)
                .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxHeight: .infinity)
    }
}

/// The small diagram icon that leads a card's title.
struct DiagramBadge: View {
    var body: some View {
        Image(systemName: "point.3.connected.trianglepath.dotted")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.1)))
    }
}

/// Shows the diagram and sweeps it in from left to right. Recreated per step via `.id`.
private struct RevealDiagram: View {
    let image: NSImage?
    @State private var progress: CGFloat = 0

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            }
        }
        .mask(alignment: .leading) {
            GeometryReader { geo in
                Rectangle().frame(width: geo.size.width * progress, height: geo.size.height)
            }
        }
        .onAppear {
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.9)) { progress = 1 }
        }
    }
}
