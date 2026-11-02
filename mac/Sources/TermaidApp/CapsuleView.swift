import AppKit
import SwiftUI

extension Color {
    static let recordRed = Color(red: 1, green: 69 / 255, blue: 58 / 255)
    static let okGreen = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
    static let caretBlue = Color(red: 10 / 255, green: 132 / 255, blue: 1)
    static let errorText = Color(red: 1, green: 0.55, blue: 0.5)
}

/// One black shape that changes size per phase, with each phase's content layered inside it.
struct CapsuleRootView: View {
    @ObservedObject var model: AppModel
    @FocusState private var typingFocused: Bool

    private var isCard: Bool { model.phase == .card || model.phase == .saved }

    var body: some View {
        let size = model.shapeSize
        let radius: CGFloat = isCard ? 30 : size.height / 2
        let curve: Animation = isCard
            ? .timingCurve(0.3, 1.12, 0.45, 1, duration: 0.76)
            : .timingCurve(0.32, 1.25, 0.5, 1, duration: 0.62)

        ZStack(alignment: .top) {
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(0.55), radius: 22, y: 10)

                ZStack {
                    hint.capsuleLayer(model.phase == .idle && model.errorMessage == nil)
                    listening.capsuleLayer(model.phase == .listening)
                    typing.capsuleLayer(model.phase == .typing)
                    working.capsuleLayer(model.phase == .working)
                    errorLine.capsuleLayer(model.phase == .idle && model.errorMessage != nil)
                    card.capsuleLayer(isCard)
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .frame(width: size.width, height: size.height)
            .animation(curve, value: size)
        }
        .frame(width: CapsuleMetrics.panelSize.width, height: CapsuleMetrics.panelSize.height, alignment: .top)
        .onChange(of: model.phase) { _, phase in
            if phase == .typing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { typingFocused = true }
            }
        }
    }

    // MARK: - Layers

    private var hint: some View {
        HStack(spacing: 10) {
            KeyChord(icon: "mic.fill", keys: ["⌥", "Space"])
            Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: 16)
            KeyChord(icon: "keyboard", keys: ["⌥", "T"])
        }
    }

    private var listening: some View {
        HStack(spacing: 12) {
            MicBadge(symbol: "mic.fill", color: .recordRed)
            // The newest words matter most, so long transcripts are cut at the start.
            Text(model.liveTranscript.isEmpty ? "Listening…" : model.liveTranscript)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(model.liveTranscript.isEmpty ? Color(white: 0.75) : .white)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 0)
            Waveform(levels: model.levels)
        }
        .padding(.leading, 9)
        .padding(.trailing, 18)
    }

    private var working: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 36, height: 36)
                .overlay(ProgressView().controlSize(.small).colorScheme(.dark))
            Text(model.workingLabel)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(white: 0.75))
            Spacer(minLength: 0)
        }
        .padding(.leading, 9)
        .padding(.trailing, 18)
    }

    private var typing: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "keyboard")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                )
            TextField("Describe a flow…", text: $model.typedText)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .tint(Color.caretBlue)
                .focused($typingFocused)
                .onSubmit { model.submitTyped() }
            KeyCap(label: "return ↵", height: 24)
        }
        .padding(.leading, 9)
        .padding(.trailing, 18)
    }

    private var errorLine: some View {
        Text(model.errorMessage ?? "")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.errorText)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 18)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.1)))
                Text(model.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                savedChip
            }
            .frame(height: 24)
            .padding(.horizontal, 2)

            transcript
            canvas
        }
        .padding(.top, 14)
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { model.openCard() }
    }

    private var savedChip: some View {
        let saved = model.phase == .saved
        return HStack(spacing: 5) {
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
        for (index, sentence) in model.sentences.enumerated() {
            if index > 0 { line = line + Text(" ") }
            let current = index == model.currentStep
            line = line + Text(sentence).foregroundColor(current ? .white : Color(white: 0.56))
        }
        return line
            .font(.system(size: 13))
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .animation(.easeOut(duration: 0.35), value: model.currentStep)
    }

    private var canvas: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 5 / 255, green: 5 / 255, blue: 6 / 255))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
            RevealDiagram(image: model.svgImage)
                .id(model.svgRevision)
                .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxHeight: .infinity)
    }
}

private extension View {
    /// Fades and blurs a phase's content in or out; hidden layers take no clicks.
    func capsuleLayer(_ on: Bool) -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(on ? 1 : 0)
            .blur(radius: on ? 0 : 6)
            .animation(.easeOut(duration: 0.3).delay(on ? 0.16 : 0), value: on)
            .allowsHitTesting(on)
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

private struct KeyChord: View {
    let icon: String
    let keys: [String]

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .padding(.trailing, 2)
            ForEach(keys, id: \.self) { KeyCap(label: $0) }
        }
        .foregroundStyle(Color(white: 0.63))
    }
}

private struct KeyCap: View {
    let label: String
    var height: CGFloat = 20

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(white: 0.85))
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: height)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
    }
}

private struct MicBadge: View {
    let symbol: String
    let color: Color
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .background(
                Circle()
                    .fill(color.opacity(pulsing ? 0 : 0.45))
                    .scaleEffect(pulsing ? 1.45 : 1)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulsing = true }
            }
    }
}

/// Bars driven by the recent input levels, newest on the right.
private struct Waveform: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(levels.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.recordRed)
                    .frame(width: 3, height: 22 * CGFloat(max(0.16, min(1, levels[index]))))
                    .animation(.linear(duration: 0.08), value: levels[index])
            }
        }
        .frame(height: 22)
    }
}
